// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Which games Steam lists as playable with a controller. Steam's store says it per game ("Full controller support" or "Partial controller support"); one request
/// answers for a few dozen games, and the answers are kept for a week.
@MainActor
final class SteamControllers: ObservableObject {
    static let shared = SteamControllers()

    private struct Entry: Codable { var level: String; var at: Double }
    private static let key = "f4.steamControllers"
    private static let maxAge: TimeInterval = 7 * 24 * 3600

    @Published private var entries: [String: Entry] = [:]
    private var fetching = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let saved = try? JSONDecoder().decode([String: Entry].self, from: data) { entries = saved }
    }

    /// What Steam says about this game, or nil when it lists no controller support (or has not been asked yet).
    func level(for appID: Int?) -> ControllerLevel? {
        guard let appID, let e = entries[String(appID)] else { return nil }
        return ControllerLevel(rawValue: e.level)
    }

    /// Games Steam has answered for: lets a screen tell "no controller support" from "not known yet".
    func isKnown(_ appID: Int) -> Bool { entries[String(appID)] != nil }

    /// Asks Steam about the games it has no fresh answer for. Safe to call often.
    func refresh(ids: [Int]) async {
        guard !fetching else { return }
        let now = Date().timeIntervalSince1970
        let wanted = Array(Set(ids)).filter { id in entries[String(id)].map { now - $0.at > Self.maxAge } ?? true }.sorted()
        guard !wanted.isEmpty else { return }
        fetching = true
        defer { fetching = false }
        var start = 0
        while start < wanted.count {
            let chunk = Array(wanted[start..<min(start + 80, wanted.count)])
            start += 80
            guard let answers = await Self.ask(chunk) else { continue }
            for (id, level) in answers { entries[String(id)] = Entry(level: level, at: now) }
            if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: Self.key) }
        }
    }

    /// appid -> "full" / "partial" / "none". Category 28 is "Full controller support", 18 is "Partial".
    private nonisolated static func ask(_ ids: [Int]) async -> [Int: String]? {
        let input: [String: Any] = ["ids": ids.map { ["appid": $0] }, "context": ["language": "english", "country_code": "US"], "data_request": [String: Any]()]
        guard let json = try? JSONSerialization.data(withJSONObject: input), let text = String(data: json, encoding: .utf8),
              var c = URLComponents(string: "https://api.steampowered.com/IStoreBrowseService/GetItems/v1") else { return nil }
        c.queryItems = [URLQueryItem(name: "input_json", value: text)]
        guard let url = c.url, let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = (root["response"] as? [String: Any])?["store_items"] as? [[String: Any]] else { return nil }
        var out: [Int: String] = [:]
        for item in items {
            guard let id = item["appid"] as? Int, (item["success"] as? Int) == 1 else { continue }
            let categories = ((item["categories"] as? [String: Any])?["controller_categoryids"] as? [Int]) ?? []
            out[id] = categories.contains(28) ? "full" : categories.contains(18) ? "partial" : "none"
        }
        return out
    }
}
