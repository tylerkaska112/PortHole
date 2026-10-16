// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import UIKit
import SwiftUI

/// Finds a game on Steam by name and fetches its artwork. Only Steam's public store search and image CDN are used; no login and none of your data is sent
/// (just the game's name, which is the search text). Pictures are cached on disk so each is downloaded once.
actor SteamArt {
    static let shared = SteamArt()

    struct Match: Identifiable, Hashable {
        let id: Int
        let name: String
        let thumb: URL?
    }

    private var memory: [Int: UIImage] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15; c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("steam-art", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Search

    func search(_ term: String) async -> [Match] {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, var comps = URLComponents(string: "https://store.steampowered.com/api/storesearch/") else { return [] }
        comps.queryItems = [.init(name: "term", value: t), .init(name: "cc", value: "us"), .init(name: "l", value: "en")]
        guard let url = comps.url, let (data, _) = try? await session.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard (item["type"] as? String) == "app", let id = item["id"] as? Int, let name = item["name"] as? String else { return nil }
            return Match(id: id, name: name, thumb: (item["tiny_image"] as? String).flatMap(URL.init(string:)))
        }
    }

    /// Words to search for, best first: the game's name, then the folder it lives in, then the exe name ("Factorio_2.0.77" -> "Factorio").
    static func searchTerms(name: String, exe: String) -> [String] {
        func clean(_ s: String) -> String {
            var out = s.replacingOccurrences(of: ".exe", with: "", options: .caseInsensitive)
            for c in ["_", "-", "."] { out = out.replacingOccurrences(of: c, with: " ") }
            let words = out.split(separator: " ").filter { w in !w.allSatisfy(\.isNumber) && !(w.first?.lowercased() == "v" && w.dropFirst().allSatisfy(\.isNumber)) }
            return words.joined(separator: " ")
        }
        let parts = exe.split(separator: "\\").map(String.init)
        var terms = [clean(name)]
        if parts.count >= 3 { terms.append(clean(parts[1])) }      // C:\<folder>\...
        if let last = parts.last { terms.append(clean(last)) }
        var seen = Set<String>()
        return terms.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// The Steam app that best matches a library game, or nil.
    func appID(name: String, exe: String) async -> Int? {
        for term in Self.searchTerms(name: name, exe: exe) {
            let results = await search(term)
            let wanted = term.lowercased()
            if let exact = results.first(where: { $0.name.lowercased() == wanted }) { return exact.id }
            if let first = results.first, first.name.lowercased().hasPrefix(wanted) || wanted.hasPrefix(first.name.lowercased()) { return first.id }
        }
        return nil
    }

    // MARK: Images

    /// Wide artwork for a card: the library hero, or the store header when a game has no hero. Cached, and shrunk before caching.
    func image(appID: Int) async -> UIImage? {
        if let m = memory[appID] { return m }
        let file = Self.cacheDir.appendingPathComponent("\(appID).jpg")
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) { memory[appID] = img; return img }
        for name in ["library_hero.jpg", "header.jpg"] {
            guard let url = URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/\(name)"),
                  let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: data) else { continue }
            let small = Self.shrink(img, maxWidth: 1000)
            if let jpg = small.jpegData(compressionQuality: 0.8) { try? jpg.write(to: file, options: .atomic) }
            memory[appID] = small
            return small
        }
        return nil
    }

    /// The store header (460x215, with the game's logo on it): what the tiles use, where the wide hero would crop the logo away.
    func header(appID: Int) async -> UIImage? {
        if let m = memory[-appID] { return m }
        let file = Self.cacheDir.appendingPathComponent("h\(appID).jpg")
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) { memory[-appID] = img; return img }
        guard let url = URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/header.jpg"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: data) else { return await image(appID: appID) }
        if let jpg = img.jpegData(compressionQuality: 0.85) { try? jpg.write(to: file, options: .atomic) }
        memory[-appID] = img
        return img
    }

    private static func shrink(_ img: UIImage, maxWidth: CGFloat) -> UIImage {
        guard img.size.width > maxWidth else { return img }
        let size = CGSize(width: maxWidth, height: img.size.height * maxWidth / img.size.width)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
