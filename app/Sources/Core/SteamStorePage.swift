// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// What Steam's public store shows for a game: description, pictures, trailers, ratings and system requirements. Read-only and anonymous (the only thing sent
/// is the game's app id). Answers are kept on disk for a day so a page opens instantly and works offline once seen.
struct SteamStorePage: Codable, Equatable {
    struct Media: Codable, Equatable, Identifiable {
        var id: String
        var title: String?
        var thumb: URL?
        var full: URL?           // the picture, or the video file / stream
        var isVideo: Bool
    }
    struct Review: Codable, Equatable, Identifiable {
        var id: String
        var text: String
        var positive: Bool
        var hours: Int
        var helpful: Int
        var date: Date
    }
    struct ReviewSummary: Codable, Equatable {
        var label: String        // "Very Positive"
        var positive: Int
        var negative: Int
        var total: Int { positive + negative }
        var percent: Int { total > 0 ? Int((Double(positive) / Double(total) * 100).rounded()) : 0 }
    }

    var appID: Int
    var name: String
    var shortDescription: String
    var about: String
    var developers: [String]
    var publishers: [String]
    var genres: [String]
    var released: String?
    var metacritic: Int?
    var headerURL: URL?
    var media: [Media]
    var minimumRequirements: String?
    var recommendedRequirements: String?
    var reviewSummary: ReviewSummary?
    var reviews: [Review]
    var fetched: Date

    var storeURL: URL { URL(string: "https://store.steampowered.com/app/\(appID)")! }
}

actor SteamStorePages {
    static let shared = SteamStorePages()
    private var memory: [Int: SteamStorePage] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    private static var dir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("steam-store", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// The page for a game: the saved copy straight away if it is fresh, otherwise fetched; an old copy is better than nothing when offline.
    func page(appID: Int, forceRefresh: Bool = false) async -> SteamStorePage? {
        let file = Self.dir.appendingPathComponent("\(appID).json")
        var cached = memory[appID]
        if cached == nil, let data = try? Data(contentsOf: file) {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
            cached = try? decoder.decode(SteamStorePage.self, from: data)
        }
        if let cached, !forceRefresh, Date().timeIntervalSince(cached.fetched) < 86_400 { memory[appID] = cached; return cached }
        if let fresh = await fetch(appID: appID) {
            memory[appID] = fresh
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
            if let data = try? encoder.encode(fresh) { try? data.write(to: file, options: .atomic) }
            return fresh
        }
        if let cached { memory[appID] = cached }
        return cached
    }

    private func fetch(appID: Int) async -> SteamStorePage? {
        async let details = json("https://store.steampowered.com/api/appdetails?appids=\(appID)&l=english&cc=us")
        async let summary = json("https://store.steampowered.com/appreviews/\(appID)?json=1&language=all&num_per_page=0&purchase_type=all")
        async let recent = json("https://store.steampowered.com/appreviews/\(appID)?json=1&language=english&filter=all&num_per_page=8&purchase_type=all")
        guard let root = await details, let entry = root["\(appID)"] as? [String: Any], (entry["success"] as? Bool) == true, let d = entry["data"] as? [String: Any] else { return nil }

        func names(_ key: String) -> [String] { (d[key] as? [String]) ?? [] }
        let genres = ((d["genres"] as? [[String: Any]]) ?? []).compactMap { $0["description"] as? String }
        let release = d["release_date"] as? [String: Any]
        var media: [SteamStorePage.Media] = []
        for m in (d["movies"] as? [[String: Any]]) ?? [] {
            let mp4 = m["mp4"] as? [String: Any], webm = m["webm"] as? [String: Any]
            let file = (mp4?["max"] as? String) ?? (mp4?["480"] as? String) ?? (m["hls_h264"] as? String) ?? (webm?["max"] as? String)
            guard let file, let id = m["id"] else { continue }
            media.append(.init(id: "v\(id)", title: m["name"] as? String, thumb: (m["thumbnail"] as? String).flatMap(URL.init(string:)), full: URL(string: file), isVideo: true))
        }
        for (i, s) in (((d["screenshots"] as? [[String: Any]]) ?? [])).enumerated() {
            media.append(.init(id: "s\(i)", title: nil, thumb: (s["path_thumbnail"] as? String).flatMap(URL.init(string:)), full: (s["path_full"] as? String).flatMap(URL.init(string:)), isVideo: false))
        }
        let req = d["pc_requirements"] as? [String: Any]

        var rs: SteamStorePage.ReviewSummary?
        if let q = (await summary)?["query_summary"] as? [String: Any], let label = q["review_score_desc"] as? String {
            let pos = q["total_positive"] as? Int ?? 0, neg = q["total_negative"] as? Int ?? 0
            if pos + neg > 0 { rs = .init(label: label, positive: pos, negative: neg) }
        }
        let reviews: [SteamStorePage.Review] = (((await recent)?["reviews"] as? [[String: Any]]) ?? []).compactMap { r in
            guard let text = r["review"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let author = r["author"] as? [String: Any]
            return .init(id: (r["recommendationid"] as? String) ?? UUID().uuidString, text: Self.plain(text), positive: (r["voted_up"] as? Bool) ?? true,
                         hours: ((author?["playtime_forever"] as? Int) ?? 0) / 60, helpful: (r["votes_up"] as? Int) ?? 0,
                         date: Date(timeIntervalSince1970: (r["timestamp_created"] as? Double) ?? 0))
        }
        return SteamStorePage(
            appID: appID, name: (d["name"] as? String) ?? "", shortDescription: Self.plain((d["short_description"] as? String) ?? ""), about: Self.plain((d["about_the_game"] as? String) ?? ""),
            developers: names("developers"), publishers: names("publishers"), genres: genres, released: release?["date"] as? String,
            metacritic: (d["metacritic"] as? [String: Any])?["score"] as? Int, headerURL: (d["header_image"] as? String).flatMap(URL.init(string:)), media: media,
            minimumRequirements: (req?["minimum"] as? String).map(Self.plain), recommendedRequirements: (req?["recommended"] as? String).map(Self.plain),
            reviewSummary: rs, reviews: reviews, fetched: Date())
    }

    private func json(_ string: String) async -> [String: Any]? {
        guard let url = URL(string: string), let (data, response) = try? await session.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Steam sends HTML (and BBCode-ish tags); the page shows plain paragraphs.
    static func plain(_ html: String) -> String {
        var s = html
        for (pattern, replacement) in [("(?i)<br\\s*/?>", "\n"), ("(?i)</(p|h[1-6]|div|ul|ol)>", "\n\n"), ("(?i)<li[^>]*>", "\u{2022} "), ("(?i)</li>", "\n"), ("<[^>]+>", ""), ("\\[/?[a-z0-9*]+[^\\]]*\\]", "")] {
            s = s.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        for (entity, ch) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&trade;", "\u{2122}"), ("&reg;", "\u{00AE}"), ("&copy;", "\u{00A9}")] {
            s = s.replacingOccurrences(of: entity, with: ch)
        }
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
