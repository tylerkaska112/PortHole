// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import LauncherCore

/// The network layer for updates, with a download progress that actually reports.
///
/// LauncherCore's own transport asks `session.download(for:delegate:)` for progress through `urlSession(_:downloadTask:didWriteData:...)`. For that async call
/// iOS delivers only the task-level callbacks to a per-task delegate, so those download callbacks never arrive: the bar stays empty and the step "skips".
/// Here the download uses a session-level delegate, where `didWriteData` is delivered. Uploads already report through `didSendBodyData`, which does work.
final class ProgressTransport: Transport, @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 30
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.badResponse }
        return (data, http)
    }

    func upload(_ request: URLRequest, fromFile file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> (Data, HTTPURLResponse) {
        let delegate = UploadProgress(progress)
        let (data, response) = try await session.upload(for: request, fromFile: file, delegate: delegate)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.badResponse }
        return (data, http)
    }

    func download(_ request: URLRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> (URL, HTTPURLResponse) {
        let job = DownloadJob(progress)
        // One session per download so the session-level delegate is this job's.
        let configuration = session.configuration
        let downloadSession = URLSession(configuration: configuration, delegate: job, delegateQueue: nil)
        defer { downloadSession.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                job.continuation = continuation
                let task = downloadSession.downloadTask(with: request)
                job.task = task
                task.resume()
            }
        } onCancel: { job.task?.cancel() }
    }
}

/// Session-level delegate for one download.
private final class DownloadJob: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>?
    var task: URLSessionDownloadTask?
    private let report: @Sendable (Double) -> Void
    private var lastReported = -1.0
    private var finishedFile: URL?
    private let lock = NSLock()

    init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        // Thousands of callbacks per download: pass on only visible changes (every 0.5%).
        lock.lock(); defer { lock.unlock() }
        if fraction - lastReported >= 0.005 || fraction >= 1 { lastReported = fraction; report(fraction) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system deletes `location` when this returns, so move it somewhere that survives.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("download-\(UUID().uuidString)")
        do { try FileManager.default.moveItem(at: location, to: kept); finishedFile = kept } catch { finishedFile = nil }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let continuation = self.continuation; self.continuation = nil
        if let error { continuation?.resume(throwing: error); return }
        guard let http = task.response as? HTTPURLResponse, let file = finishedFile else { continuation?.resume(throwing: NetworkError.badResponse); return }
        continuation?.resume(returning: (file, http))
    }
}

private final class UploadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        report(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}
