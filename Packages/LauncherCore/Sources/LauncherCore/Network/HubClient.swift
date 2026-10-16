// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// The update server a build is pointed at (the Hub): where the app finds its own newer builds. Read-only: this client never sends the person's
/// files or any account data, and a signed build is never uploaded anywhere (it is signed and installed on the device).
///
///   GET  /apps.json                       the apps the Hub knows (id, name, bundle id, newest build)
///   GET  /updates/<app id>/…              the `/updates` API, per app
public struct HubClient: Sendable {
    public let baseURL: URL
    private let transport: any Transport

    public init(baseURL: URL, transport: any Transport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport
    }

    public struct HubApp: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let bundleId: String
        public let latest: Release?
    }

    /// Access to an app's builds on the Hub, through the same client every other source uses.
    public func updates(forApp id: String) -> UpdatesClient {
        UpdatesClient(baseURL: baseURL.appendingPathComponent("updates").appendingPathComponent(id), transport: transport)
    }

    public func apps() async throws -> [HubApp] {
        var request = URLRequest(url: baseURL.appendingPathComponent("apps.json"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, response) = try await transport.data(for: request)
        if response.statusCode == 404 { return [] }
        try UpdatesClient.check(response, data)
        do { return try JSONDecoder().decode([HubApp].self, from: data) }
        catch { throw NetworkError.decoding(error.localizedDescription) }
    }
}
