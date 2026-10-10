// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

enum StreamingDownloadError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "installer.error.invalid_response", defaultValue: "Le serveur a renvoyé une réponse invalide.")
        case .httpStatus(let status):
            String(localized: "installer.error.http_status", defaultValue: "Le téléchargement a échoué (HTTP \(status)).")
        }
    }
}

/// Télécharge directement vers le volume choisi, sans doubler les poids
/// dans le cache interne de macOS. Un fichier `.part` est repris via HTTP Range.
final class StreamingHTTPDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias ProgressHandler = @Sendable (_ receivedBytes: Int64, _ totalBytes: Int64) async -> Void

    private let sourceURL: URL
    private let partialURL: URL
    private let expectedBytes: Int64
    private let progress: ProgressHandler
    private let lock = NSLock()
    private let delegateQueue: OperationQueue

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var continuation: CheckedContinuation<Void, Error>?
    private var terminalError: Error?
    private var receivedBytes: Int64 = 0
    private var lastProgressUpdate = Date.distantPast

    init(
        sourceURL: URL,
        partialURL: URL,
        expectedBytes: Int64,
        progress: @escaping ProgressHandler
    ) {
        self.sourceURL = sourceURL
        self.partialURL = partialURL
        self.expectedBytes = expectedBytes
        self.progress = progress
        delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .utility
        super.init()
    }

    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { self.continuation = continuation }

                guard !Task.isCancelled else {
                    finish(.failure(CancellationError()))
                    return
                }

                do {
                    let parent = partialURL.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                    if !FileManager.default.fileExists(atPath: partialURL.path) {
                        FileManager.default.createFile(atPath: partialURL.path, contents: nil)
                    }

                    let attributes = try FileManager.default.attributesOfItem(atPath: partialURL.path)
                    receivedBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                    if receivedBytes > expectedBytes {
                        try FileManager.default.removeItem(at: partialURL)
                        FileManager.default.createFile(atPath: partialURL.path, contents: nil)
                        receivedBytes = 0
                    }

                    var request = URLRequest(url: sourceURL)
                    request.timeoutInterval = 7_200
                    request.setValue("NanoApple/0.1 (macOS; local model installer)", forHTTPHeaderField: "User-Agent")
                    if receivedBytes > 0 {
                        request.setValue("bytes=\(receivedBytes)-", forHTTPHeaderField: "Range")
                    }

                    let configuration = URLSessionConfiguration.default
                    configuration.timeoutIntervalForRequest = 120
                    configuration.timeoutIntervalForResource = 7_200
                    configuration.waitsForConnectivity = true
                    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
                    self.session = session
                    let task = session.dataTask(with: request)
                    self.task = task
                    task.resume()
                } catch {
                    finish(.failure(error))
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        lock.withLock { task }?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            terminalError = StreamingDownloadError.invalidResponse
            completionHandler(.cancel)
            return
        }

        guard response.statusCode == 200 || response.statusCode == 206 else {
            terminalError = StreamingDownloadError.httpStatus(response.statusCode)
            completionHandler(.cancel)
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: partialURL)
            if response.statusCode == 206, receivedBytes > 0 {
                try handle.seekToEnd()
            } else {
                try handle.truncate(atOffset: 0)
                receivedBytes = 0
            }
            fileHandle = handle
            completionHandler(.allow)
        } catch {
            terminalError = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try fileHandle?.write(contentsOf: data)
            receivedBytes += Int64(data.count)

            let now = Date()
            if now.timeIntervalSince(lastProgressUpdate) >= 0.15 || receivedBytes >= expectedBytes {
                lastProgressUpdate = now
                let received = receivedBytes
                let total = expectedBytes
                Task { await progress(received, total) }
            }
        } catch {
            terminalError = error
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        try? fileHandle?.synchronize()
        try? fileHandle?.close()
        fileHandle = nil

        if let terminalError {
            finish(.failure(terminalError))
        } else if let error {
            if (error as? URLError)?.code == .cancelled {
                finish(.failure(CancellationError()))
            } else {
                finish(.failure(error))
            }
        } else {
            finish(.success(()))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            let value = self.continuation
            self.continuation = nil
            return value
        }
        guard let continuation else { return }
        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
