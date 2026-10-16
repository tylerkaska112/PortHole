// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// A big file (an itch.io upload, a GOG installer part) fetched in pieces by byte-range requests, many at once, and written in order. One HTTP connection rarely carries a
/// download at the speed a phone's Wi-Fi can; a window of ranges does (ChunkWindow). Because the file is filled front to back, the same resume rule as the single
/// stream applies: a `.part` file of N bytes continues at byte N.
enum SegmentedDownload {
    static let segment = 8 * 1024 * 1024

    private static func session() -> URLSession {
        let configuration = StoreNetwork.configuration()
        configuration.httpMaximumConnectionsPerHost = 32
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration)
    }

    /// Returns false, having written nothing, when the server does not do range requests (the caller then uses the single stream).
    static func fetch(url: URL, to file: URL, onProgress: @escaping @Sendable (UInt64) -> Void) async throws -> Bool {
        let session = session()
        defer { session.finishTasksAndInvalidate() }
        let have = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.uint64Value ?? 0

        // Probe: the first byte at the resume point. A server that answers 200 sends the whole file, which is never read here.
        var probe = URLRequest(url: url)
        probe.timeoutInterval = 30
        probe.setValue("bytes=\(have)-\(have)", forHTTPHeaderField: "Range")
        let (stream, response) = try await session.bytes(for: probe)
        guard let http = response as? HTTPURLResponse else { return false }
        if http.statusCode == 416 { return true }   // already complete
        guard http.statusCode == 206, let range = http.value(forHTTPHeaderField: "Content-Range"), let slash = range.lastIndex(of: "/"),
              let total = UInt64(range[range.index(after: slash)...]), total > have else { return false }
        _ = stream   // not read: dropping it ends the request

        let remaining = total - have
        let count = Int((remaining + UInt64(segment) - 1) / UInt64(segment))
        LogStore.shared.log("[download] \(remaining / 1_048_576) MB in \(count) range request(s) of \(segment / 1_048_576) MB, resuming at \(have / 1_048_576) MB")
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()

        func bounds(_ i: Int) -> (UInt64, UInt64) {
            let from = have + UInt64(i) * UInt64(segment)
            return (from, min(total, from + UInt64(segment)) - 1)
        }
        let window = ChunkWindow<Int>(order: Array(0..<count), weight: { i in let b = bounds(i); return Int(b.1 - b.0 + 1) }, start: 8, floor: 4, ceiling: 32, fetch: { i in
            let (from, to) = bounds(i)
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            request.setValue("bytes=\(from)-\(to)", forHTTPHeaderField: "Range")
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 206, UInt64(data.count) == to - from + 1 else { throw URLError(.badServerResponse) }
            return (data, data.count)
        })
        defer { window.cancel() }
        var written = have
        for i in 0..<count {
            try Task.checkCancellation()
            let data = try await window.take(i)
            try handle.write(contentsOf: data)
            written += UInt64(data.count)
            onProgress(written)
        }
        guard written == total else { throw GogInstallError.invalid("The download ended early. Try again (it carries on from where it stopped).") }
        return true
    }
}

extension GogFileFetcher {
    /// Many range requests at once when the server allows it, else the single stream.
    static func fetchFast(url: URL, to file: URL, onProgress: @escaping @Sendable (UInt64) -> Void) async throws {
        do {
            if try await SegmentedDownload.fetch(url: url, to: file, onProgress: onProgress) { return }
        } catch is CancellationError { throw CancellationError() }
        catch { LogStore.shared.log("[download] range download failed (\(error.localizedDescription)); using the single stream", level: .info) }
        try await fetch(url: url, to: file, onProgress: onProgress)
    }
}
