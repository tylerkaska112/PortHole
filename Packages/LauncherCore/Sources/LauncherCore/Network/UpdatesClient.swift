// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import CryptoKit

/// Reads one server's `/updates` folder: the newest build, every build with its changelog, and the IPAs themselves.
/// All of the Launcher's sources (Home server, Slicer server, Waylon server, the Hub) answer the same way.
public struct UpdatesClient: Sendable {
    public let baseURL: URL
    private let transport: any Transport

    public init(baseURL: URL, transport: any Transport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport
    }

    /// The newest published build, or `nil` when nothing has been published yet (the server answers 404).
    public func latest() async throws -> Release? {
        let (data, response) = try await transport.data(for: request("latest.json"))
        if response.statusCode == 404 { return nil }
        try Self.check(response, data)
        do { return resolved(try JSONDecoder().decode(Release.self, from: data)) }
        catch { throw NetworkError.decoding(error.localizedDescription) }
    }

    /// Every build on the server, newest first. Entries that can't be read are skipped, never the whole list.
    public func versions() async throws -> [Release] {
        let (data, response) = try await transport.data(for: request("versions.json"))
        if response.statusCode == 404 { return [] }
        try Self.check(response, data)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [Any] else { throw NetworkError.decoding("versions.json isn't a list") }
        let decoder = JSONDecoder()
        return array.compactMap { item in
            guard let json = try? JSONSerialization.data(withJSONObject: item), let release = try? decoder.decode(Release.self, from: json) else { return nil }
            return resolved(release)
        }.sorted { lhs, rhs in
            lhs.buildNumber != rhs.buildNumber ? lhs.buildNumber > rhs.buildNumber : AppVersion.compare(lhs.version, rhs.version) == .orderedDescending
        }
    }

    /// Downloads a build into `directory` and checks its SHA-256 when the server published one. Returns the file.
    public func download(_ release: Release, to directory: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        let url = release.url ?? baseURL.appendingPathComponent("files").appendingPathComponent(release.file)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        let (temporary, response) = try await transport.download(request, progress: progress)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard response.statusCode == 200 else { throw NetworkError.server(status: response.statusCode, message: "The download failed (\(response.statusCode)).") }
        try Task.checkCancellation()
        if let wanted = release.sha256?.lowercased(), !wanted.isEmpty, try Self.sha256(of: temporary) != wanted { throw NetworkError.damaged }
        let target = directory.appendingPathComponent(Self.safeName(release.file))
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
        return target
    }

    // MARK: Helpers

    private func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        return request
    }

    /// Fills in the download address when the server sent none.
    private func resolved(_ release: Release) -> Release {
        guard release.url == nil else { return release }
        var copy = release
        copy.url = baseURL.appendingPathComponent("files").appendingPathComponent(release.file)
        return copy
    }

    static func check(_ response: HTTPURLResponse, _ data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? ""
            throw NetworkError.server(status: response.statusCode, message: message)
        }
    }

    static func safeName(_ file: String) -> String { file.replacingOccurrences(of: "/", with: "_") }

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
