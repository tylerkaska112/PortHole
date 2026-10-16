// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

// Some games need a second Steam app installed before Valve's client will start them. The one that matters is "Steamworks Common Redistributables" (app 228980, folder
// "Steamworks Shared"): the games' own install scripts and their DirectX / Visual C++ runtimes come from it. Valve's client in the prefix queues its download ("Update Required,
// Update Queued") but never starts it, so a game that needs it is refused with launch error 17 ("required app 228980 not ready") for as long as it waits. Porthole's own downloader
// does work for any app, so it installs this one itself before a Steam launch that needs it.
enum SteamSharedApps {
    static let commonRedistributables = 228980
    /// The shared apps Porthole knows how to provide, with the name Steam gives them.
    static let known: [Int: String] = [commonRedistributables: "Steamworks Common Redistributables"]

    /// The known shared apps a game's depots come from (a depot "from app 228980" is one the game takes out of that app).
    static func needed(by depots: [SteamDepot], gameID: Int) -> [Int] {
        let sources = Set(depots.compactMap { $0.fromApp }).subtracting([gameID])
        return known.keys.filter { sources.contains($0) }.sorted()
    }

    /// Whether the text of an `appmanifest_<id>.acf` records a finished install (state 4, with at least one depot).
    static func isInstalled(recordText text: String) -> Bool {
        guard let root = SteamVDF.parse(text), let state = root["appstate"] as? [String: Any] else { return false }
        guard (state["stateflags"] as? String) == "4" else { return false }
        return !((state["installeddepots"] as? [String: Any]) ?? [:]).isEmpty
    }

    static func isInstalled(appID: Int, steamApps: URL) -> Bool {
        let url = steamApps.appendingPathComponent("appmanifest_\(appID).acf")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return isInstalled(recordText: text)
    }
}
