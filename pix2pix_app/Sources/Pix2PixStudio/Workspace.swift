import AppKit
import Foundation

struct Workspace {
    private let fm = FileManager.default
    let support: URL
    let models: URL
    let datasets: URL
    let runtime: URL
    let incoming: URL
    let defaultOutput: URL
    let frames: URL
    let nextFrame: URL
    let nextFrameModels: URL
    let nextFrameModel: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        support = home.appendingPathComponent("Library/Application Support/Pix2Pix Studio", isDirectory: true)
        models = support.appendingPathComponent("Models", isDirectory: true)
        datasets = support.appendingPathComponent("Datasets", isDirectory: true)
        runtime = support.appendingPathComponent("Runtime", isDirectory: true)
        incoming = support.appendingPathComponent("Incoming", isDirectory: true)
        defaultOutput = home.appendingPathComponent("Pictures/Pix2Pix Studio", isDirectory: true)
        frames = defaultOutput.appendingPathComponent("frames", isDirectory: true)
        nextFrame = support.appendingPathComponent("Next Frame", isDirectory: true)
        nextFrameModels = nextFrame.appendingPathComponent("Models", isDirectory: true)
        nextFrameModel = nextFrame.appendingPathComponent("latest_net_G.pth")
    }

    func createDirectories(output: URL? = nil) throws {
        for url in [support, models, datasets, runtime, incoming, defaultOutput, frames, nextFrame, nextFrameModels, output ?? defaultOutput] {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    func nextFrameModelURLs() -> [URL] {
        var urls: [URL] = []
        if fm.fileExists(atPath: nextFrameModel.path) { urls.append(nextFrameModel) }
        if let stored = try? fm.contentsOfDirectory(
            at: nextFrameModels,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            urls += stored.filter { $0.pathExtension.lowercased() == "pth" }
        }
        return urls.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
    }

    func modelDirectory(_ preset: Pix2PixPreset) -> URL {
        models.appendingPathComponent(preset.rawValue, isDirectory: true)
    }

    func datasetDirectory(_ package: DatasetPackage) -> URL {
        datasets.appendingPathComponent(package.rawValue, isDirectory: true)
    }

    func modelIsInstalled(_ preset: Pix2PixPreset) -> Bool {
        switch preset {
        case .cats:
            guard let items = try? fm.subpathsOfDirectory(atPath: modelDirectory(preset).path) else { return false }
            return items.contains(where: { $0.hasSuffix("export.meta") })
        default:
            return fm.fileExists(atPath: modelDirectory(preset).appendingPathComponent("latest_net_G.pth").path)
        }
    }

    func datasetIsInstalled(_ package: DatasetPackage) -> Bool {
        guard let contents = try? fm.contentsOfDirectory(atPath: datasetDirectory(package).path) else { return false }
        return !contents.isEmpty
    }
}

final class DownloadService: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var destination: URL?
    private var progressHandler: ((Double) -> Void)?
    private var session: URLSession?

    func download(from source: URL, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.destination = destination
            self.progressHandler = progress
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 600
            configuration.timeoutIntervalForResource = 60 * 60 * 24
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: source).resume()
        }
    }

    func cancel() {
        session?.invalidateAndCancel()
        finish(.failure(CancellationError()))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let destination else { throw AppError.message("The download destination was lost.") }
            if let response = downloadTask.response as? HTTPURLResponse,
               !(200...299).contains(response.statusCode) {
                throw AppError.message("The download server returned HTTP \(response.statusCode).")
            }
            let size = (try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 1_000_000 else { throw AppError.message("The server returned an incomplete download.") }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        progressHandler = nil
        session?.finishTasksAndInvalidate()
        session = nil
        switch result {
        case .success: continuation.resume()
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}

struct CommandRunner {
    static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil, onStart: @escaping (Process) -> Void = { _ in }, onLine: @escaping (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            if let environment { process.environment = environment }

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    text.split(whereSeparator: \ .isNewline).forEach { onLine(String($0)) }
                }
            }
            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AppError.message("A helper process exited with code \(process.terminationStatus)."))
                }
            }
            do {
                try process.run()
                onStart(process)
            } catch { continuation.resume(throwing: error) }
        }
    }
}
