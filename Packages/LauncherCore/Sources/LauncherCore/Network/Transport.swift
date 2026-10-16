// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// The few things the Launcher asks of the network, so tests can answer them without one.
public protocol Transport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Downloads to a temporary file (the caller moves it), reporting 0…1 as it arrives.
    func download(_ request: URLRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> (URL, HTTPURLResponse)
    /// Uploads a file as the request body.
    func upload(_ request: URLRequest, fromFile file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> (Data, HTTPURLResponse)
}

public enum NetworkError: Error, LocalizedError, Equatable {
    case badResponse
    case server(status: Int, message: String)
    case decoding(String)
    case damaged
    case notConfigured(String)

    public var errorDescription: String? {
        switch self {
        case .badResponse: "The server sent something unexpected."
        case .server(let status, let message): message.isEmpty ? "The server answered \(status)." : message
        case .decoding(let detail): "Couldn't read the server's answer (\(detail))."
        case .damaged: "The download was damaged (its checksum doesn't match). Try again."
        case .notConfigured(let what): what
        }
    }
}

public final class URLSessionTransport: Transport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = URLSessionTransport.makeSession()) { self.session = session }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 30
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.badResponse }
        return (data, http)
    }

    public func download(_ request: URLRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> (URL, HTTPURLResponse) {
        // `session.download(for:delegate:)` never delivers `didWriteData` to a per-task delegate, so a progress bar built on it stays at 0%. A
        // session-level delegate does get it: one session per download, so the delegate belongs to this download alone.
        let job = DownloadJob(progress)
        let downloadSession = URLSession(configuration: session.configuration, delegate: job, delegateQueue: nil)
        defer { downloadSession.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                job.start(downloadSession.downloadTask(with: request), continuation)
            }
        } onCancel: { job.cancel() }
    }

    public func upload(_ request: URLRequest, fromFile file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> (Data, HTTPURLResponse) {
        let delegate = ProgressDelegate(progress)
        let (data, response) = try await session.upload(for: request, fromFile: file, delegate: delegate)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.badResponse }
        return (data, http)
    }
}

/// Reports upload progress (0…1) as bytes move. (Uploads report fine through the async API; downloads do not, see `DownloadJob`.)
final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        report(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}


/// One download, as the session-level delegate of its own session: reports 0…1 as bytes arrive and hands back the finished file.
final class DownloadJob: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>?
    private var task: URLSessionDownloadTask?
    private var lastReported = -1.0
    private var finishedFile: URL?

    init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func start(_ task: URLSessionDownloadTask, _ continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>) {
        lock.lock(); self.task = task; self.continuation = continuation; lock.unlock()
        task.resume()
    }

    func cancel() { lock.lock(); let task = self.task; lock.unlock(); task?.cancel() }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        // Thousands of callbacks per download: pass on only visible changes (every 0.5%).
        lock.lock()
        let send = fraction - lastReported >= 0.005 || fraction >= 1
        if send { lastReported = fraction }
        lock.unlock()
        if send { report(fraction) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system deletes `location` when this returns, so move it somewhere that survives.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("download-\(UUID().uuidString)")
        let moved = (try? FileManager.default.moveItem(at: location, to: kept)) != nil
        lock.lock(); finishedFile = moved ? kept : nil; lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let continuation = self.continuation; self.continuation = nil; let file = finishedFile; lock.unlock()
        if let error { continuation?.resume(throwing: error); return }
        guard let http = task.response as? HTTPURLResponse, let file else { continuation?.resume(throwing: NetworkError.badResponse); return }
        continuation?.resume(returning: (file, http))
    }
}
