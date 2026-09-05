import AppKit
import CoreImage
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var page: SidebarPage? = .studio
    @Published var preset: Pix2PixPreset = .handbags
    @Published var inputURL: URL?
    @Published var inputImage: NSImage?
    @Published var keepWholeImage = false
    @Published var outputURL: URL?
    @Published var outputImage: NSImage?
    @Published var exportSize: ExportSize = .px512
    @Published var outputDirectory: URL
    @Published var isWorking = false
    @Published var activity = "Ready"
    @Published var progress: Double?
    @Published var log: [String] = []
    @Published var errorMessage: String?
    @Published var modelStates: [Pix2PixPreset: Bool] = [:]
    @Published var datasetStates: [DatasetPackage: Bool] = [:]

    let workspace = Workspace()
    private var downloader: DownloadService?
    private var sourceInputURL: URL?

    init() {
        outputDirectory = Workspace().defaultOutput
        do { try workspace.createDirectories(output: outputDirectory) }
        catch { errorMessage = error.localizedDescription }
        refreshInstallStates()
    }

    func refreshInstallStates() {
        modelStates = Dictionary(uniqueKeysWithValues: Pix2PixPreset.allCases.map { ($0, workspace.modelIsInstalled($0)) })
        datasetStates = Dictionary(uniqueKeysWithValues: DatasetPackage.allCases.map { ($0, workspace.datasetIsInstalled($0)) })
    }

    func chooseInputImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { loadInput(url) }
    }

    func loadInput(_ url: URL, prepareSquare: Bool = true) {
        guard let image = NSImage(contentsOf: url) else {
            errorMessage = "That file is not an image macOS can read."
            return
        }
        sourceInputURL = url
        var preparedURL = url
        var preparedImage = image
        if prepareSquare, let result = squareImage(image, sourceName: url.deletingPathExtension().lastPathComponent, addMargins: keepWholeImage) {
            preparedURL = result.url
            preparedImage = result.image
        }
        inputURL = preparedURL
        inputImage = preparedImage
        outputURL = nil
        outputImage = nil
        activity = "\(keepWholeImage ? "White margins" : "Center crop") ready · \(Int(preparedImage.size.width)) px"
    }

    func reprepareInput() {
        if let sourceInputURL { loadInput(sourceInputURL) }
    }

    private func squareImage(_ image: NSImage, sourceName: String, addMargins: Bool) -> (url: URL, image: NSImage)? {
        let side = addMargins ? max(image.size.width, image.size.height) : min(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let bucket: CGFloat = side <= 256 ? 256 : (side <= 512 ? 512 : 1024)
        let output = NSImage(size: NSSize(width: bucket, height: bucket))
        output.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: bucket, height: bucket)).fill()
        NSGraphicsContext.current?.imageInterpolation = .high
        if addMargins {
            let scale = min(bucket / image.size.width, bucket / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let destination = NSRect(x: (bucket - size.width) / 2, y: (bucket - size.height) / 2, width: size.width, height: size.height)
            image.draw(in: destination, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        } else {
            let source = NSRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
            image.draw(in: NSRect(x: 0, y: 0, width: bucket, height: bucket), from: source, operation: .copy, fraction: 1)
        }
        output.unlockFocus()
        guard let tiff = output.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let safeName = sourceName.replacingOccurrences(of: "/", with: "-")
        let mode = addMargins ? "margins" : "crop"
        let url = workspace.incoming.appendingPathComponent("\(safeName)-\(mode)-\(Int(bucket))-\(UUID().uuidString.prefix(6)).png")
        do { try png.write(to: url); return (url, output) } catch { return nil }
    }

    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else { return false }
        let incomingDirectory = workspace.incoming
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
            guard let self, let url, error == nil else { return }
            let target = incomingDirectory.appendingPathComponent("drop-\(UUID().uuidString).\(url.pathExtension.isEmpty ? "png" : url.pathExtension)")
            do {
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: url, to: target)
                Task { @MainActor in self.loadInput(target) }
            } catch { Task { @MainActor in self.errorMessage = error.localizedDescription } }
        }
        return true
    }

    func prepareEdges() {
        guard let inputImage, let data = inputImage.tiffRepresentation, let ci = CIImage(data: data) else { return }
        let edges = CIFilter(name: "CIEdges", parameters: [kCIInputImageKey: ci, kCIInputIntensityKey: 7.0])?.outputImage
        let inverted = edges.flatMap { CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: $0])?.outputImage }
        guard let result = inverted, let cg = CIContext().createCGImage(result, from: result.extent) else {
            errorMessage = "macOS could not create an edge map from this image."
            return
        }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let url = workspace.incoming.appendingPathComponent("edges-\(UUID().uuidString).png")
        do { try png.write(to: url); loadInput(url); activity = "Edge map ready" }
        catch { errorMessage = error.localizedDescription }
    }

    func useSketch(_ strokes: [SketchStroke]) {
        let size = NSSize(width: 256, height: 256)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        NSColor.black.setStroke()
        for stroke in strokes where stroke.points.count > 1 {
            let path = NSBezierPath()
            path.lineWidth = 4
            path.lineCapStyle = .round
            path.move(to: stroke.points[0])
            for point in stroke.points.dropFirst() { path.line(to: point) }
            path.stroke()
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = workspace.incoming.appendingPathComponent("sketch-\(UUID().uuidString).png")
        do { try png.write(to: url); loadInput(url); activity = "Sketch ready" }
        catch { errorMessage = error.localizedDescription }
    }

    func installModel(_ item: Pix2PixPreset) {
        guard !isWorking else { return }
        Task {
            await perform("Installing \(item.shortTitle) model") {
                try await self.ensureRuntime(for: item)
                let directory = self.workspace.modelDirectory(item)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if item == .cats {
                    let archive = directory.appendingPathComponent("cats-model.tar.gz")
                    try await self.download([URL(string: "https://github.com/knok/pix2pix-tensorflow/releases/download/v1.0/export-cats-model.tar.gz")!], to: archive)
                    try await self.run("/usr/bin/tar", ["-xzf", archive.path, "-C", directory.path])
                    try? FileManager.default.removeItem(at: archive)
                } else {
                    let collection = item.isCycleGAN ? "cyclegan/pretrained_models" : "pix2pix/models-pytorch"
                    let official = URL(string: "https://efrosgans.eecs.berkeley.edu/\(collection)/\(item.checkpointName).pth")!
                    var sources = [official]
                    if let id = item.mirrorFileID {
                        let mirror = URL(string: "https://drive.usercontent.google.com/download?id=\(id)&export=download&confirm=t")!
                        sources.insert(mirror, at: 0)
                    }
                    try await self.download(sources, to: directory.appendingPathComponent("latest_net_G.pth"))
                }
            }
        }
    }

    func installDataset(_ item: DatasetPackage) {
        if item == .cityscapes {
            NSWorkspace.shared.open(URL(string: "https://www.cityscapes-dataset.com/downloads/")!)
            activity = "Cityscapes requires its free account and license"
            return
        }
        guard !isWorking else { return }
        Task {
            await perform("Downloading \(item.title)") {
                let directory = self.workspace.datasetDirectory(item)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let archive = directory.appendingPathComponent("download.tar.gz")
                let source: URL
                if item == .edges2cats {
                    source = URL(string: "https://github.com/knok/pix2pix-tensorflow/releases/download/v1.0/edge2cats-dataset.tar.gz")!
                } else {
                    source = URL(string: "https://efrosgans.eecs.berkeley.edu/pix2pix/datasets/\(item.rawValue).tar.gz")!
                }
                try await self.download([source], to: archive)
                if item == .edges2cats {
                    try await self.run("/usr/bin/tar", ["-xzf", archive.path, "-C", directory.path])
                } else {
                    try await self.run("/usr/bin/tar", ["-xzf", archive.path, "-C", self.workspace.datasets.path])
                }
                try? FileManager.default.removeItem(at: archive)
            }
        }
    }

    func generate() {
        guard !isWorking, let inputURL else { return }
        guard workspace.modelIsInstalled(preset) else {
            errorMessage = "Install the \(preset.shortTitle) model first."
            page = .downloads
            return
        }
        Task {
            await perform("Generating with \(preset.shortTitle)") {
                try await self.ensureRuntime(for: self.preset)
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let result = self.outputDirectory.appendingPathComponent("\(self.preset.rawValue)-\(stamp).png")
                let model = self.workspace.modelDirectory(self.preset)
                let modelPath = self.preset == .cats ? model.path : model.appendingPathComponent("latest_net_G.pth").path
                let python = self.workspace.runtime.appendingPathComponent(self.preset == .cats ? "cats/bin/python" : "pytorch/bin/python")
                let backend = self.workspace.runtime.appendingPathComponent("pix2pix_backend.py")
                try PythonBackend.source.write(to: backend, atomically: true, encoding: .utf8)
                try await self.run(python.path, [backend.path, "--architecture", self.preset.backendArchitecture, "--model", modelPath, "--input", inputURL.path, "--output", result.path, "--output-size", String(self.exportSize.rawValue)])
                guard let image = NSImage(contentsOf: result) else { throw AppError.message("The model finished without a readable output image.") }
                self.outputURL = result
                self.outputImage = image
            }
        }
    }

    private func ensureRuntime(for item: Pix2PixPreset) async throws {
        let name = item == .cats ? "cats" : "pytorch"
        let venv = workspace.runtime.appendingPathComponent(name)
        let python = venv.appendingPathComponent("bin/python")
        if !FileManager.default.fileExists(atPath: python.path) {
            guard let base = ["/opt/homebrew/bin/python3.11", "/opt/homebrew/bin/python3.12", "/usr/local/bin/python3.11", "/usr/bin/python3"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                throw AppError.message("Python 3.10–3.12 is required. Install Python with Homebrew, then try again.")
            }
            try await run(base, ["-m", "venv", venv.path])
            try await run(python.path, ["-m", "pip", "install", "--upgrade", "pip"])
            if item == .cats {
                try await run(python.path, ["-m", "pip", "install", "tensorflow", "pillow", "numpy<2"])
            } else {
                try await run(python.path, ["-m", "pip", "install", "torch", "torchvision", "pillow", "numpy"])
            }
        }
    }

    private func download(_ sources: [URL], to destination: URL) async throws {
        var lastError: Error?
        for (index, source) in sources.enumerated() {
            let service = DownloadService()
            downloader = service
            do {
                try await service.download(from: source, to: destination) { value in
                    Task { @MainActor in self.progress = value; self.activity = "Downloading… \(Int(value * 100))%" }
                }
                downloader = nil; progress = nil
                return
            } catch {
                lastError = error
                log.append("Source \(index + 1) failed; trying the next mirror.")
            }
        }
        downloader = nil; progress = nil
        throw lastError ?? AppError.message("No download source was available.")
    }

    private func run(_ executable: String, _ arguments: [String]) async throws {
        try await CommandRunner.run(executable, arguments, environment: ProcessInfo.processInfo.environment) { line in
            Task { @MainActor in self.log.append(line); self.activity = line }
        }
    }

    private func perform(_ title: String, operation: () async throws -> Void) async {
        isWorking = true; activity = title; progress = nil; errorMessage = nil; log = []
        do { try await operation(); activity = "Done" }
        catch {
            let details = log.suffix(6).joined(separator: "\n")
            errorMessage = details.isEmpty ? error.localizedDescription : "\(error.localizedDescription)\n\n\(details)"
            activity = "Stopped"
        }
        isWorking = false; progress = nil; refreshInstallStates()
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func revealOutputFolder() { try? workspace.createDirectories(output: outputDirectory); NSWorkspace.shared.open(outputDirectory) }
    func revealSupportFolder() { NSWorkspace.shared.open(workspace.support) }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.directoryURL = outputDirectory; panel.prompt = "Use This Folder"
        if panel.runModal() == .OK, let url = panel.url { outputDirectory = url; try? workspace.createDirectories(output: url) }
    }

    func createOutputFolder() {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let folder = outputDirectory.appendingPathComponent("Pix2Pix \(formatter.string(from: Date()))", isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); outputDirectory = folder; NSWorkspace.shared.open(folder) }
        catch { errorMessage = error.localizedDescription }
    }

    func saveResultAs() {
        guard let outputURL else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = outputURL.lastPathComponent
        if panel.runModal() == .OK, let target = panel.url {
            do { try? FileManager.default.removeItem(at: target); try FileManager.default.copyItem(at: outputURL, to: target) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
