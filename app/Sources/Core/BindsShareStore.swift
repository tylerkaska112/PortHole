// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

// The Hub calls for shared bind sets, over the same signed channel compatibility reports use (the install's own P-256 key; see CompatCore.swift).

extension CompatClient {
    private func bindsPath(_ tail: String) -> String { "/binds/" + tail }
    private func gamePath(_ id: String) -> String { bindsPath("games/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id) + "/sets") }

    func sharedBinds(gameID: String, sort: String, limit: Int = 30, offset: Int = 0) async throws -> [SharedBind] {
        try await get(gamePath(gameID), [("sort", sort), ("limit", String(limit)), ("offset", String(offset))], as: [SharedBind].self)
    }
    func sharedBind(id: Int) async throws -> SharedBind { try await get(bindsPath("sets/\(id)"), as: SharedBind.self) }
    func sharedBindReviews(id: Int, limit: Int = 30, offset: Int = 0) async throws -> [SharedBindReview] {
        try await get(bindsPath("sets/\(id)/reviews"), [("limit", String(limit)), ("offset", String(offset))], as: [SharedBindReview].self)
    }
    func publishBind(_ payload: BindPublishPayload) async throws -> BindPublishResult {
        try await signed("POST", bindsPath("sets"), body: try JSONEncoder().encode(payload), as: BindPublishResult.self)
    }
    func countBindDownload(id: Int) async throws { _ = try await signed("POST", bindsPath("sets/\(id)/download"), as: Done.self) }
    func reviewBind(id: Int, thumbUp: Bool, comment: String) async throws -> BindReviewResult {
        struct Body: Encodable { var thumb: String; var comment: String }
        return try await signed("POST", bindsPath("sets/\(id)/reviews"), body: try JSONEncoder().encode(Body(thumb: thumbUp ? "up" : "down", comment: comment)), as: BindReviewResult.self)
    }
    func flagBind(id: Int) async throws { _ = try await signed("POST", bindsPath("sets/\(id)/flag"), as: Done.self) }
    func deleteBind(id: Int) async throws { _ = try await signed("DELETE", bindsPath("sets/\(id)"), as: Done.self) }
    func myBinds() async throws -> [MySharedBind] { try await signed("GET", bindsPath("mine"), as: [MySharedBind].self) }
}

/// What the screens use: finding a game's id on the Hub, publishing, downloading, reviewing.
@MainActor
final class BindsShareStore: ObservableObject {
    static let shared = BindsShareStore()
    @Published private(set) var mine: [Int: MySharedBind] = [:]     // by the Hub's id

    private var client: CompatClient { CompatClient.standard() }
    var available: Bool { client.baseURL != nil }

    /// The id a game's shared sets are filed under, and how to name the game when publishing: a Steam game downloaded here by its app id, anything else by the
    /// fingerprint of its program (the same references compatibility reports use). nil when the game can not be identified (an installer, or a program that can't be read).
    func gameRef(for game: Game) async -> (id: String, ref: BindGameRef)? {
        let compat = CompatStore.shared
        guard let r = await compat.gameRef(for: game, source: game.dockAppID != nil ? .steam : .other) else { return nil }
        if r.kind == "steam", let app = r.steamAppID { return ("steam:\(app)", BindGameRef(kind: "steam", steamAppID: app, fingerprint: nil, title: r.title)) }
        if let fp = r.fingerprint { return ("file:\(fp.prefix(32))", BindGameRef(kind: "file", steamAppID: nil, fingerprint: fp, title: r.title)) }
        return nil
    }

    /// A 404 from the list or publish address means the update server does not run the sharing service (yet): they never answer 404 otherwise.
    private func serviceMissing<T>(_ work: () async throws -> T) async throws -> T {
        do { return try await work() }
        catch CompatError.server(let code, _) where code == 404 { throw CompatError.notAvailable("Sharing is not switched on on the update server yet.") }
    }

    func list(gameID: String, sort: String) async throws -> [SharedBind] { try await serviceMissing { try await client.sharedBinds(gameID: gameID, sort: sort) } }
    func detail(id: Int) async throws -> SharedBind { try await client.sharedBind(id: id) }
    func reviews(id: Int) async throws -> [SharedBindReview] { try await client.sharedBindReviews(id: id) }

    func refreshMine() async {
        guard available, let rows = try? await client.myBinds() else { return }
        mine = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }

    func publish(_ set: BindSet, for game: Game) async throws -> BindPublishResult {
        guard let g = await gameRef(for: game) else { throw CompatError.notAvailable("Porthole can't tell which game this is yet. Open the game's page again in a moment, or start the game once.") }
        let result = try await serviceMissing { try await client.publishBind(BindPublishPayload(set: set, game: g.ref)) }
        await refreshMine()
        return result
    }

    func unpublish(remoteID: Int) async throws {
        try await client.deleteBind(id: remoteID)
        mine[remoteID] = nil
    }

    func review(id: Int, thumbUp: Bool, comment: String) async throws -> BindReviewResult { try await client.reviewBind(id: id, thumbUp: thumbUp, comment: comment) }
    func flag(id: Int) async throws { try await client.flagBind(id: id) }
    /// Counts a download for the author (once per install); a failure here never stops the download itself.
    func countDownload(id: Int) async { try? await client.countBindDownload(id: id) }
}
