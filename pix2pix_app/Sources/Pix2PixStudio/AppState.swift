import AppKit
import AVFoundation
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
    @Published var animationEnabled = false
    @Published var animationSteps = 12
    @Published var isAnimating = false
    @Published var completedAnimationFrames = 0
    @Published var nfpTrainingVideoURL: URL?
    @Published var nfpEpochs = 10
    @Published var nfpMaxTrainingFrames = 600
    @Published var nfpFrameCount = 120
    @Published var nfpModelInstalled = false
    @Published var nfpModels: [URL] = []
    @Published var selectedNFPModelURL: URL?
    @Published var isNFPTraining = false
    @Published var isNFPPredicting = false
    @Published var completedNFPFrames = 0
    @Published var nfpAnchorToStartingFrame = true
    @Published var styleGANPreset: StyleGANPreset = .ffhq
    @Published var styleGANModelStates: [StyleGANPreset: Bool] = [:]
    @Published var styleGANModels: [URL] = []
    @Published var selectedStyleGANModelURL: URL?
    @Published var styleGANMode: StyleGANMode = .latent
    @Published var styleGANVideoURL: URL?
    @Published var styleGANVideoThumbnail: NSImage?
    @Published var styleGANKeyframes = 4
    @Published var styleGANVideoKeyframes = 4
    @Published var styleGANTransitionFrames = 48
    @Published var styleGANFPS = 24
    @Published var styleGANSeed = 42
    @Published var styleGANDistance = 1.0
    @Published var styleGANTruncation = 0.7
    @Published var styleGANInterpolation: StyleGANInterpolation = .smooth
    @Published var styleGANNoise: StyleGANNoiseMode = .constant
    @Published var styleGANLoop = true
    @Published var styleGANStyleMix = 0.0
    @Published var styleGANStyleCutoff = 8
    @Published var styleGANVideoFit: StyleGANVideoFit = .fit
    @Published var styleGANProjectionSteps = 100
    @Published var styleGANClassIndex = 0
    @Published var isStyleGANRunning = false
    @Published var completedStyleGANFrames = 0
    @Published var totalStyleGANFrames = 0
    @Published var styleGANOutputVideoURL: URL?
    @Published var styleGANTrainingVideos: [URL] = []
    @Published var styleGANTrainingName = "My Video Model"
    @Published var styleGANTrainingMaxFrames = 600
    @Published var styleGANTrainingFrameStep = 3
    @Published var styleGANTrainingEpochs = 5
    @Published var styleGANTrainingBatchSize = 1
    @Published var styleGANTrainingLearningRate = 0.002
    @Published var styleGANTrainingAugment = true
    @Published var styleGANTrainingSize: StyleGANTrainingSize = .balanced256
    @Published var completedStyleGANTrainingSteps = 0
    @Published var totalStyleGANTrainingSteps = 0

    let workspace = Workspace()
    private var downloader: DownloadService?
    private var sourceInputURL: URL?
    private var animationTask: Task<Void, Never>?
    private var activeProcess: Process?
    private var nfpTask: Task<Void, Never>?
    private var styleGANTask: Task<Void, Never>?

    init() {
        outputDirectory = Workspace().defaultOutput
        do { try workspace.createDirectories(output: outputDirectory) }
        catch { errorMessage = error.localizedDescription }
        refreshInstallStates()
    }

    func refreshInstallStates() {
        modelStates = Dictionary(uniqueKeysWithValues: Pix2PixPreset.allCases.map { ($0, workspace.modelIsInstalled($0)) })
        datasetStates = Dictionary(uniqueKeysWithValues: DatasetPackage.allCases.map { ($0, workspace.datasetIsInstalled($0)) })
        styleGANModelStates = Dictionary(uniqueKeysWithValues: StyleGANPreset.allCases.map { ($0, workspace.styleGANModelIsInstalled($0)) })
        styleGANModels = workspace.styleGANModelURLs()
        if let selectedStyleGANModelURL, FileManager.default.fileExists(atPath: selectedStyleGANModelURL.path) {
            // Keep the active checkpoint.
        } else if let savedPath = UserDefaults.standard.string(forKey: "selectedStyleGANModelPath"),
                  FileManager.default.fileExists(atPath: savedPath) {
            selectedStyleGANModelURL = URL(fileURLWithPath: savedPath)
        } else if workspace.styleGANModelIsInstalled(styleGANPreset) {
            selectedStyleGANModelURL = workspace.styleGANModelURL(styleGANPreset)
        } else {
            selectedStyleGANModelURL = styleGANModels.first
        }
        if let selectedStyleGANModelURL {
            if let official = StyleGANPreset.allCases.first(where: { workspace.styleGANModelURL($0) == selectedStyleGANModelURL }) {
                styleGANPreset = official
            } else {
                let name = selectedStyleGANModelURL.deletingPathExtension().lastPathComponent.lowercased()
                if let base = StyleGANPreset.allCases.first(where: { name.contains("-\($0.rawValue)-") }) { styleGANPreset = base }
            }
        }
        nfpModels = workspace.nextFrameModelURLs()
        if let selectedNFPModelURL, FileManager.default.fileExists(atPath: selectedNFPModelURL.path) {
            // Keep the current selection when refreshing the library.
        } else if let savedPath = UserDefaults.standard.string(forKey: "selectedNFPModelPath"),
                  FileManager.default.fileExists(atPath: savedPath) {
            selectedNFPModelURL = URL(fileURLWithPath: savedPath)
        } else {
            selectedNFPModelURL = nfpModels.first
        }
        nfpModelInstalled = selectedNFPModelURL != nil
    }

    func selectStyleGANModel(_ url: URL?) {
        selectedStyleGANModelURL = url
        if let url {
            UserDefaults.standard.set(url.path, forKey: "selectedStyleGANModelPath")
            activity = "Selected StyleGAN2 checkpoint · \(styleGANModelDisplayName(url))"
            if let official = StyleGANPreset.allCases.first(where: { workspace.styleGANModelURL($0) == url }) {
                styleGANPreset = official
            } else {
                let name = url.lastPathComponent
                if let base = StyleGANPreset.allCases.first(where: { name.contains("-\($0.rawValue)-") }) { styleGANPreset = base }
            }
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedStyleGANModelPath")
        }
    }

    func selectOfficialStyleGANPreset(_ preset: StyleGANPreset) {
        styleGANPreset = preset
        let url = workspace.styleGANModelURL(preset)
        if FileManager.default.fileExists(atPath: url.path) { selectStyleGANModel(url) }
        else { selectStyleGANModel(nil) }
    }

    func styleGANModelDisplayName(_ url: URL) -> String {
        if let official = StyleGANPreset.allCases.first(where: { workspace.styleGANModelURL($0) == url }) {
            return official.title
        }
        return url.deletingPathExtension().lastPathComponent
    }

    func selectNFPModel(_ url: URL?) {
        selectedNFPModelURL = url
        nfpModelInstalled = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        if let url {
            UserDefaults.standard.set(url.path, forKey: "selectedNFPModelPath")
            activity = "Selected next-frame model · \(nfpModelDisplayName(url))"
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedNFPModelPath")
        }
    }

    func revealNFPModelsFolder() {
        do {
            try workspace.createDirectories()
            NSWorkspace.shared.open(workspace.nextFrameModels)
        } catch {
            errorMessage = "Could not open the model folder: \(error.localizedDescription)"
        }
    }

    func nfpModelDisplayName(_ url: URL) -> String {
        url == workspace.nextFrameModel ? "Previously Trained Model" : url.deletingPathExtension().lastPathComponent
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
        guard !isWorking else { return false }
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
        guard let inputImage else { return }
        let url = workspace.incoming.appendingPathComponent("edges-\(UUID().uuidString).png")
        do { try writeEdgeMap(from: inputImage, to: url); loadInput(url); activity = "Edge map ready" }
        catch { errorMessage = error.localizedDescription }
    }

    private func writeEdgeMap(from image: NSImage, to url: URL) throws {
        guard let data = image.tiffRepresentation, let ci = CIImage(data: data) else {
            throw AppError.message("macOS could not read the image for edge detection.")
        }
        let edges = CIFilter(name: "CIEdges", parameters: [kCIInputImageKey: ci, kCIInputIntensityKey: 7.0])?.outputImage
        let inverted = edges.flatMap { CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: $0])?.outputImage }
        guard let result = inverted, let cg = CIContext().createCGImage(result, from: result.extent) else {
            throw AppError.message("macOS could not create an edge map from this image.")
        }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AppError.message("macOS could not encode the edge map.")
        }
        try png.write(to: url)
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

    func installStyleGANModel(_ item: StyleGANPreset) {
        guard !isWorking else { return }
        Task {
            await perform("Installing \(item.shortTitle) StyleGAN2 model") {
                try self.workspace.createDirectories()
                try await self.ensureStyleGANRuntime()
                try await self.download([item.downloadURL], to: self.workspace.styleGANModelURL(item))
                self.selectStyleGANModel(self.workspace.styleGANModelURL(item))
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
                try await self.runModel(input: inputURL, output: result, preset: self.preset, size: self.exportSize)
                guard let image = NSImage(contentsOf: result) else { throw AppError.message("The model finished without a readable output image.") }
                self.outputURL = result
                self.outputImage = image
            }
        }
    }

    func startAnimation() {
        guard !isWorking, let startingInput = inputURL else { return }
        guard workspace.modelIsInstalled(preset) else {
            errorMessage = "Install the \(preset.shortTitle) model first."
            page = .downloads
            return
        }
        animationSteps = min(max(animationSteps, 1), 10_000)
        let requestedSteps = animationSteps
        let selectedPreset = preset
        let selectedSize = exportSize
        animationTask = Task { [weak self] in
            guard let self else { return }
            self.isWorking = true
            self.isAnimating = true
            self.completedAnimationFrames = 0
            self.errorMessage = nil
            self.log = []
            do {
                try self.workspace.createDirectories()
                try await self.ensureRuntime(for: selectedPreset)
                let runStamp = Self.animationTimestamp()
                var source = startingInput
                for frameNumber in 1...requestedSteps {
                    try Task.checkCancellation()
                    self.activity = "Animation frame \(frameNumber) of \(requestedSteps) · making edges"
                    let edgeURL = self.workspace.incoming.appendingPathComponent("animation-edge-\(UUID().uuidString).png")
                    guard let sourceImage = NSImage(contentsOf: source) else {
                        throw AppError.message("Frame \(frameNumber) could not be read for edge detection.")
                    }
                    try self.writeEdgeMap(from: sourceImage, to: edgeURL)
                    defer { try? FileManager.default.removeItem(at: edgeURL) }

                    try Task.checkCancellation()
                    self.activity = "Animation frame \(frameNumber) of \(requestedSteps) · generating"
                    let number = String(format: "%04d", frameNumber)
                    let result = self.workspace.frames.appendingPathComponent("\(runStamp)-\(selectedPreset.rawValue)-frame-\(number).png")
                    try await self.runModel(input: edgeURL, output: result, preset: selectedPreset, size: selectedSize)
                    try Task.checkCancellation()
                    guard let resultImage = NSImage(contentsOf: result) else {
                        throw AppError.message("The model did not produce a readable frame \(frameNumber).")
                    }
                    self.outputURL = result
                    self.outputImage = resultImage
                    self.completedAnimationFrames = frameNumber
                    source = result
                }
                self.activity = "Animation complete · \(requestedSteps) frames"
            } catch {
                if Task.isCancelled {
                    self.activity = "Animation stopped · \(self.completedAnimationFrames) frames saved"
                } else {
                    let details = self.log.suffix(6).joined(separator: "\n")
                    self.errorMessage = details.isEmpty ? error.localizedDescription : "\(error.localizedDescription)\n\n\(details)"
                    self.activity = "Animation stopped by an error"
                }
            }
            self.activeProcess = nil
            self.isAnimating = false
            self.isWorking = false
            self.animationTask = nil
        }
    }

    func stopAnimation() {
        guard isAnimating else { return }
        activity = "Stopping animation…"
        animationTask?.cancel()
        activeProcess?.terminate()
    }

    func stopAllWork() {
        animationTask?.cancel()
        nfpTask?.cancel()
        styleGANTask?.cancel()
        activeProcess?.terminate()
        downloader?.cancel()
    }

    func chooseStyleGANVideo() {
        guard !isWorking else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.item]
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Video"
        if panel.runModal() == .OK, let url = panel.url { setStyleGANVideo(url) }
    }

    func chooseStyleGANTrainingVideos() {
        guard !isWorking else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.item]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Training Videos"
        if panel.runModal() == .OK { appendStyleGANTrainingVideos(panel.urls) }
    }

    func acceptStyleGANTrainingVideoDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !isWorking else { return false }
        let matching = providers.compactMap { provider -> (NSItemProvider, String)? in
            guard let identifier = Self.bestFileRepresentationType(for: provider) else { return nil }
            return (provider, identifier)
        }
        guard !matching.isEmpty else { return false }
        for (provider, identifier) in matching {
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { [weak self] url, error in
                guard let self, let url, error == nil else { return }
                Task { @MainActor in
                    let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                    let target = self.workspace.incoming.appendingPathComponent("stylegan-training-\(UUID().uuidString).\(ext)")
                    do {
                        try FileManager.default.copyItem(at: url, to: target)
                        self.appendStyleGANTrainingVideos([target])
                    } catch { self.errorMessage = error.localizedDescription }
                }
            }
        }
        return true
    }

    private func appendStyleGANTrainingVideos(_ urls: [URL]) {
        for url in urls where !styleGANTrainingVideos.contains(url) { styleGANTrainingVideos.append(url) }
        if styleGANVideoThumbnail == nil, let first = styleGANTrainingVideos.first {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: first))
            generator.appliesPreferredTrackTransform = true
            if let image = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                styleGANVideoThumbnail = NSImage(cgImage: image, size: .zero)
            }
        }
        activity = "StyleGAN2 training dataset · \(styleGANTrainingVideos.count) video\(styleGANTrainingVideos.count == 1 ? "" : "s")"
    }

    func clearStyleGANTrainingVideos() {
        styleGANTrainingVideos = []
        styleGANVideoThumbnail = nil
        activity = "StyleGAN2 training videos cleared"
    }

    func acceptStyleGANVideoDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !isWorking else { return false }
        guard let provider = providers.first(where: { Self.bestFileRepresentationType(for: $0) != nil }),
              let identifier = Self.bestFileRepresentationType(for: provider) else { return false }
        let incoming = workspace.incoming
        provider.loadFileRepresentation(forTypeIdentifier: identifier) { [weak self] url, error in
            guard let self, let url, error == nil else { return }
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let target = incoming.appendingPathComponent("stylegan-video-\(UUID().uuidString).\(ext)")
            do {
                try FileManager.default.copyItem(at: url, to: target)
                Task { @MainActor in self.setStyleGANVideo(target) }
            } catch { Task { @MainActor in self.errorMessage = error.localizedDescription } }
        }
        return true
    }

    private func setStyleGANVideo(_ url: URL) {
        styleGANVideoURL = url
        styleGANVideoThumbnail = nil
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let image = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            styleGANVideoThumbnail = NSImage(cgImage: image, size: .zero)
        }
        activity = "StyleGAN2 video ready · \(url.lastPathComponent)"
    }

    func revealStyleGANModels() {
        try? workspace.createDirectories()
        NSWorkspace.shared.open(workspace.styleGANModels)
    }

    func revealStyleGANOutput() {
        try? workspace.createDirectories()
        NSWorkspace.shared.open(workspace.styleGANOutput)
    }

    func revealStyleGANDatasets() {
        try? workspace.createDirectories()
        NSWorkspace.shared.open(workspace.styleGANDatasets)
    }

    func runStyleGAN() {
        guard !isWorking else { return }
        guard styleGANMode != .training else { trainStyleGAN(); return }
        guard let modelURL = selectedStyleGANModelURL,
              FileManager.default.fileExists(atPath: modelURL.path) else {
            errorMessage = "Download or choose a StyleGAN2 checkpoint first."
            return
        }
        if styleGANMode == .video && styleGANVideoURL == nil {
            errorMessage = "Drop or choose a video to project first."
            return
        }
        styleGANKeyframes = min(max(styleGANKeyframes, 2), 12)
        styleGANVideoKeyframes = min(max(styleGANVideoKeyframes, 2), 16)
        styleGANTransitionFrames = min(max(styleGANTransitionFrames, 2), 600)
        styleGANFPS = min(max(styleGANFPS, 1), 60)
        styleGANProjectionSteps = min(max(styleGANProjectionSteps, 10), 1_000)
        styleGANSeed = max(styleGANSeed, 0)
        styleGANDistance = min(max(styleGANDistance, 0), 4)
        styleGANTruncation = min(max(styleGANTruncation, 0), 2)
        styleGANStyleMix = min(max(styleGANStyleMix, 0), 1)
        styleGANStyleCutoff = min(max(styleGANStyleCutoff, 0), 32)

        let preset = styleGANPreset
        let mode = styleGANMode
        let video = styleGANVideoURL
        let keyframes = mode == .video ? styleGANVideoKeyframes : styleGANKeyframes
        let segments = styleGANLoop ? keyframes : keyframes - 1
        totalStyleGANFrames = segments * styleGANTransitionFrames + (styleGANLoop ? 0 : 1)
        let runDirectory = workspace.styleGANOutput.appendingPathComponent("\(Self.styleGANTimestamp())-\(preset.rawValue)", isDirectory: true)
        let selectedSize = exportSize
        let transitionFrames = styleGANTransitionFrames
        let fps = styleGANFPS
        let seed = styleGANSeed
        let distance = styleGANDistance
        let truncation = styleGANTruncation
        let interpolation = styleGANInterpolation
        let noise = styleGANNoise
        let loop = styleGANLoop
        let styleMix = styleGANStyleMix
        let styleCutoff = styleGANStyleCutoff
        let fit = styleGANVideoFit
        let projectionSteps = styleGANProjectionSteps
        let classIndex = styleGANClassIndex

        styleGANTask = Task { [weak self] in
            guard let self else { return }
            self.isWorking = true; self.isStyleGANRunning = true
            self.completedStyleGANFrames = 0; self.styleGANOutputVideoURL = nil
            self.errorMessage = nil; self.log = []
            do {
                try self.workspace.createDirectories()
                try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
                try await self.ensureStyleGANRuntime()
                let backend = self.workspace.runtime.appendingPathComponent("stylegan_backend.py")
                try StyleGANBackend.source.write(to: backend, atomically: true, encoding: .utf8)
                let python = self.workspace.runtime.appendingPathComponent("pytorch/bin/python")
                var arguments = [backend.path,
                    "--source", self.workspace.styleGANSource.path,
                    "--model", modelURL.path,
                    "--output-dir", runDirectory.path,
                    "--cache-dir", self.workspace.styleGANRuntime.appendingPathComponent("Torch Cache").path,
                    "--mode", mode == .video ? "video" : "latent",
                    "--keyframes", String(self.styleGANKeyframes),
                    "--video-keyframes", String(self.styleGANVideoKeyframes),
                    "--projection-steps", String(projectionSteps),
                    "--fit", fit.backendValue,
                    "--transition-frames", String(transitionFrames),
                    "--fps", String(fps),
                    "--output-size", String(selectedSize.rawValue),
                    "--seed", String(seed),
                    "--distance", String(distance),
                    "--truncation", String(truncation),
                    "--interpolation", interpolation.rawValue.lowercased(),
                    "--noise", noise.backendValue,
                    "--style-mix", String(styleMix),
                    "--style-cutoff", String(styleCutoff),
                    "--class-index", String(classIndex)]
                if loop { arguments.append("--loop") }
                if let video, mode == .video { arguments += ["--video", video.path] }
                self.activity = mode == .video ? "Projecting source video into StyleGAN2" : "Beginning StyleGAN2 latent journey"
                try await self.run(python.path, arguments) { line in
                    if line.hasPrefix("STYLEGAN frame "), let divider = line.firstIndex(of: "|") {
                        let report = String(line[..<divider])
                        let path = String(line[line.index(after: divider)...])
                        let parts = report.split(separator: " ")
                        if parts.count > 2, let frame = Int(parts[2]) { self.completedStyleGANFrames = frame }
                        let url = URL(fileURLWithPath: path)
                        if let image = NSImage(contentsOf: url) { self.outputURL = url; self.outputImage = image }
                        self.activity = report
                    } else if line.hasPrefix("STYLEGAN video|") {
                        self.styleGANOutputVideoURL = URL(fileURLWithPath: String(line.dropFirst("STYLEGAN video|".count)))
                    }
                }
                self.activity = "StyleGAN2 animation complete · \(self.completedStyleGANFrames) frames"
            } catch {
                if Task.isCancelled { self.activity = "StyleGAN2 stopped · \(self.completedStyleGANFrames) frames saved" }
                else { self.showProcessError(error, prefix: "StyleGAN2 failed") }
            }
            self.activeProcess = nil; self.isStyleGANRunning = false; self.isWorking = false; self.styleGANTask = nil
        }
    }

    func trainStyleGAN() {
        guard !isWorking else { return }
        guard !styleGANTrainingVideos.isEmpty else {
            errorMessage = "Drop or choose at least one source video for training."
            return
        }
        guard let baseModel = selectedStyleGANModelURL,
              FileManager.default.fileExists(atPath: baseModel.path) else {
            errorMessage = "Download or choose a base StyleGAN2 checkpoint first."
            return
        }

        styleGANTrainingMaxFrames = min(max(styleGANTrainingMaxFrames, 8), 10_000)
        styleGANTrainingFrameStep = min(max(styleGANTrainingFrameStep, 1), 300)
        styleGANTrainingEpochs = min(max(styleGANTrainingEpochs, 1), 500)
        styleGANTrainingBatchSize = min(max(styleGANTrainingBatchSize, 1), 8)
        styleGANTrainingLearningRate = min(max(styleGANTrainingLearningRate, 0.00001), 0.01)

        let videos = styleGANTrainingVideos
        let preset = styleGANPreset
        let maxFrames = styleGANTrainingMaxFrames
        let frameStep = styleGANTrainingFrameStep
        let epochs = styleGANTrainingEpochs
        let batchSize = styleGANTrainingBatchSize
        let learningRate = styleGANTrainingLearningRate
        let augment = styleGANTrainingAugment
        let trainingSize = styleGANTrainingSize
        let fit = styleGANVideoFit
        let classIndex = styleGANClassIndex
        let stamp = Self.styleGANTimestamp()
        let safeName = Self.safeStyleGANName(styleGANTrainingName)
        let checkpointResolution = Self.styleGANCheckpointResolution(baseModel, fallback: preset.nativeResolution)
        let requestedResolution = trainingSize.rawValue == 0 ? checkpointResolution : min(trainingSize.rawValue, checkpointResolution)
        let outputModel = workspace.styleGANModels.appendingPathComponent("trained-\(preset.rawValue)-\(requestedResolution)px-\(safeName)-\(stamp).pkl")
        let datasetDirectory = workspace.styleGANDatasets.appendingPathComponent("\(safeName)-\(stamp)", isDirectory: true)

        styleGANTask = Task { [weak self] in
            guard let self else { return }
            self.isWorking = true; self.isStyleGANRunning = true
            self.completedStyleGANTrainingSteps = 0; self.totalStyleGANTrainingSteps = 0
            self.styleGANOutputVideoURL = nil; self.errorMessage = nil; self.log = []
            do {
                try self.workspace.createDirectories()
                try await self.ensureStyleGANRuntime()
                let backend = self.workspace.runtime.appendingPathComponent("stylegan_training_backend.py")
                try StyleGANTrainingBackend.source.write(to: backend, atomically: true, encoding: .utf8)
                let python = self.workspace.runtime.appendingPathComponent("pytorch/bin/python")
                var arguments = [backend.path,
                    "--source", self.workspace.styleGANSource.path,
                    "--base-model", baseModel.path,
                    "--output-model", outputModel.path,
                    "--dataset-dir", datasetDirectory.path,
                    "--max-frames", String(maxFrames),
                    "--frame-step", String(frameStep),
                    "--epochs", String(epochs),
                    "--batch-size", String(batchSize),
                    "--learning-rate", String(learningRate),
                    "--training-resolution", String(trainingSize.rawValue),
                    "--fit", fit.backendValue,
                    "--class-index", String(classIndex)]
                if augment { arguments.append("--augment") }
                for video in videos { arguments += ["--video", video.path] }
                self.activity = "Preparing \(videos.count) video\(videos.count == 1 ? "" : "s") for StyleGAN2 training"
                try await self.run(python.path, arguments) { line in
                    if line.hasPrefix("STYLEGAN TRAIN step ") {
                        let words = line.split(separator: " ")
                        if words.count > 5, let complete = Int(words[3]), let total = Int(words[5]) {
                            self.completedStyleGANTrainingSteps = complete
                            self.totalStyleGANTrainingSteps = total
                        }
                    } else if line.hasPrefix("STYLEGAN TRAIN preview "), let divider = line.firstIndex(of: "|") {
                        let path = String(line[line.index(after: divider)...])
                        let url = URL(fileURLWithPath: path)
                        if let image = NSImage(contentsOf: url) { self.outputURL = url; self.outputImage = image }
                    } else if line.hasPrefix("STYLEGAN TRAIN saved|") {
                        let url = URL(fileURLWithPath: String(line.dropFirst("STYLEGAN TRAIN saved|".count)))
                        self.refreshInstallStates()
                        self.selectStyleGANModel(url)
                    }
                }
                self.refreshInstallStates()
                self.selectStyleGANModel(outputModel)
                self.activity = "StyleGAN2 model trained · \(self.styleGANModelDisplayName(outputModel))"
            } catch {
                if Task.isCancelled { self.activity = "StyleGAN2 training stopped · extracted frames were kept" }
                else { self.showProcessError(error, prefix: "StyleGAN2 training failed") }
            }
            self.activeProcess = nil; self.isStyleGANRunning = false; self.isWorking = false; self.styleGANTask = nil
        }
    }

    func stopStyleGAN() {
        guard isStyleGANRunning else { return }
        activity = "Stopping StyleGAN2…"
        styleGANTask?.cancel()
        activeProcess?.terminate()
    }

    func revealFramesFolder() {
        try? workspace.createDirectories()
        NSWorkspace.shared.open(workspace.frames)
    }

    func chooseNFPTrainingVideo() {
        guard !isWorking else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.item]
        panel.allowsMultipleSelection = false
        panel.prompt = "Use for Training"
        if panel.runModal() == .OK { nfpTrainingVideoURL = panel.url }
    }

    func trainNFPModel() {
        guard !isWorking, let video = nfpTrainingVideoURL else { return }
        nfpEpochs = min(max(nfpEpochs, 1), 500)
        nfpMaxTrainingFrames = min(max(nfpMaxTrainingFrames, 3), 10_000)
        let epochs = nfpEpochs
        let maxFrames = nfpMaxTrainingFrames
        let modelURL = newNFPModelURL(for: video)
        nfpTask = Task { [weak self] in
            guard let self else { return }
            self.isWorking = true; self.isNFPTraining = true
            self.errorMessage = nil; self.log = []
            do {
                try self.workspace.createDirectories()
                try await self.ensureRuntime(for: .handbags)
                let python = self.workspace.runtime.appendingPathComponent("pytorch/bin/python")
                self.activity = "Preparing the next-frame training runtime"
                try await self.run(python.path, ["-m", "pip", "install", "imageio-ffmpeg"])
                let backend = self.workspace.runtime.appendingPathComponent("nfp_backend.py")
                try NFPBackend.source.write(to: backend, atomically: true, encoding: .utf8)
                self.activity = "Extracting consecutive frames"
                try await self.run(python.path, [backend.path, "train", "--video", video.path, "--model", modelURL.path, "--epochs", String(epochs), "--max-frames", String(maxFrames)])
                self.refreshInstallStates()
                self.selectNFPModel(modelURL)
                self.activity = "Next-frame model trained · \(self.nfpModelDisplayName(modelURL))"
            } catch {
                if Task.isCancelled { self.activity = "Next-frame training stopped" }
                else { self.showProcessError(error, prefix: "Next-frame training failed") }
            }
            self.activeProcess = nil; self.isNFPTraining = false; self.isWorking = false; self.nfpTask = nil
            self.refreshInstallStates()
        }
    }

    func predictNextFrames() {
        guard !isWorking, let seed = inputURL else { return }
        guard let selectedModel = selectedNFPModelURL,
              FileManager.default.fileExists(atPath: selectedModel.path) else {
            errorMessage = "Choose or train a next-frame model first."
            return
        }
        nfpFrameCount = min(max(nfpFrameCount, 1), 10_000)
        let requestedFrames = nfpFrameCount
        let selectedSize = exportSize
        nfpTask = Task { [weak self] in
            guard let self else { return }
            self.isWorking = true; self.isNFPPredicting = true; self.completedNFPFrames = 0
            self.errorMessage = nil; self.log = []
            do {
                try self.workspace.createDirectories()
                try await self.ensureRuntime(for: .handbags)
                let python = self.workspace.runtime.appendingPathComponent("pytorch/bin/python")
                let backend = self.workspace.runtime.appendingPathComponent("nfp_backend.py")
                try NFPBackend.source.write(to: backend, atomically: true, encoding: .utf8)
                let prefix = "\(Self.animationTimestamp())-nfp"
                self.activity = "Predicting frame 1 of \(requestedFrames)"
                var arguments = [backend.path, "predict", "--model", selectedModel.path, "--input", seed.path, "--output-dir", self.workspace.frames.path, "--prefix", prefix, "--frames", String(requestedFrames), "--output-size", String(selectedSize.rawValue)]
                if self.nfpAnchorToStartingFrame { arguments.append("--anchor-to-seed") }
                try await self.run(python.path, arguments) { line in
                    guard line.hasPrefix("NFP frame "), let separator = line.firstIndex(of: "|") else { return }
                    let report = String(line[..<separator])
                    let path = String(line[line.index(after: separator)...])
                    let pieces = report.split(separator: " ")
                    if pieces.count > 2, let frame = Int(pieces[2]) { self.completedNFPFrames = frame }
                    let url = URL(fileURLWithPath: path)
                    if let image = NSImage(contentsOf: url) { self.outputURL = url; self.outputImage = image }
                    self.activity = report
                }
                self.activity = "Next-frame prediction complete · \(requestedFrames) frames"
            } catch {
                if Task.isCancelled { self.activity = "Prediction stopped · \(self.completedNFPFrames) frames saved" }
                else { self.showProcessError(error, prefix: "Next-frame prediction failed") }
            }
            self.activeProcess = nil; self.isNFPPredicting = false; self.isWorking = false; self.nfpTask = nil
        }
    }

    func stopNFP() {
        guard isNFPTraining || isNFPPredicting else { return }
        activity = "Stopping next-frame process…"
        nfpTask?.cancel()
        activeProcess?.terminate()
    }

    private func showProcessError(_ error: Error, prefix: String) {
        let details = log.suffix(8).joined(separator: "\n")
        errorMessage = details.isEmpty ? "\(prefix): \(error.localizedDescription)" : "\(prefix)\n\n\(details)"
        activity = prefix
    }

    private static func animationTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "animation-\(formatter.string(from: Date()))"
    }

    private static func styleGANTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "stylegan2-\(formatter.string(from: Date()))"
    }

    private static func safeStyleGANName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let words = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "-")
        let safe = words.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(safe).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "video-model" : result
    }

    private static func bestFileRepresentationType(for provider: NSItemProvider) -> String? {
        let identifiers = provider.registeredTypeIdentifiers
        return identifiers.first(where: { UTType($0)?.conforms(to: .fileURL) == true })
            ?? identifiers.first(where: { UTType($0)?.conforms(to: .movie) == true })
            ?? identifiers.first(where: { UTType($0)?.conforms(to: .audiovisualContent) == true })
            ?? identifiers.first(where: { UTType($0)?.conforms(to: .data) == true })
            ?? identifiers.first
    }

    private static func styleGANCheckpointResolution(_ url: URL, fallback: Int) -> Int {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        for resolution in [64, 128, 256, 512, 1024, 2048] where name.contains("-\(resolution)px-") {
            return resolution
        }
        return fallback
    }

    private func newNFPModelURL(for video: URL) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let source = video.deletingPathExtension().lastPathComponent
        let safeName = source.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let trimmed = String(safeName).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Next Frame" : trimmed
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return workspace.nextFrameModels.appendingPathComponent("\(name) — \(formatter.string(from: Date())).pth")
    }

    private func runModel(input: URL, output: URL, preset: Pix2PixPreset, size: ExportSize) async throws {
        let model = workspace.modelDirectory(preset)
        let modelPath = preset == .cats ? model.path : model.appendingPathComponent("latest_net_G.pth").path
        let python = workspace.runtime.appendingPathComponent(preset == .cats ? "cats/bin/python" : "pytorch/bin/python")
        let backend = workspace.runtime.appendingPathComponent("pix2pix_backend.py")
        try PythonBackend.source.write(to: backend, atomically: true, encoding: .utf8)
        try await run(python.path, [backend.path, "--architecture", preset.backendArchitecture, "--model", modelPath, "--input", input.path, "--output", output.path, "--output-size", String(size.rawValue)])
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

    private func ensureStyleGANRuntime() async throws {
        try await ensureRuntime(for: .handbags)
        let python = workspace.runtime.appendingPathComponent("pytorch/bin/python")
        let marker = workspace.styleGANRuntime.appendingPathComponent("runtime-ready")
        if !FileManager.default.fileExists(atPath: marker.path) {
            activity = "Installing StyleGAN2 video support"
            try await run(python.path, ["-m", "pip", "install", "imageio-ffmpeg", "click", "requests", "tqdm", "ninja"])
            try Data().write(to: marker)
        }
        let legacy = workspace.styleGANSource.appendingPathComponent("legacy.py")
        if !FileManager.default.fileExists(atPath: legacy.path) {
            activity = "Installing the official NVIDIA StyleGAN2 engine"
            let archive = workspace.styleGANRuntime.appendingPathComponent("stylegan2-source.zip")
            try await download([URL(string: "https://github.com/NVlabs/stylegan2-ada-pytorch/archive/refs/heads/main.zip")!], to: archive, minimumBytes: 50_000)
            try await run("/usr/bin/ditto", ["-x", "-k", archive.path, workspace.styleGANRuntime.path])
            try? FileManager.default.removeItem(at: archive)
            guard FileManager.default.fileExists(atPath: legacy.path) else {
                throw AppError.message("The official StyleGAN2 source archive could not be installed.")
            }
        }
    }

    private func download(_ sources: [URL], to destination: URL, minimumBytes: Int = 1_000_000) async throws {
        var lastError: Error?
        for (index, source) in sources.enumerated() {
            let service = DownloadService()
            downloader = service
            do {
                try await service.download(from: source, to: destination, minimumBytes: minimumBytes) { value in
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

    private func run(_ executable: String, _ arguments: [String], lineHandler: ((String) -> Void)? = nil) async throws {
        defer { activeProcess = nil }
        try await CommandRunner.run(executable, arguments, environment: ProcessInfo.processInfo.environment, onStart: { process in
            Task { @MainActor in self.activeProcess = process }
        }) { line in
            Task { @MainActor in
                self.log.append(line)
                self.activity = line
                lineHandler?(line)
            }
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
