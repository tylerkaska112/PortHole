// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// "Use what works for others": the settings most people who rate a game "works great" report (the Hub's summary of compatibility reports) set against how this game is
/// set up now. Only settings that differ, and only where most of those people agree, are suggested; nothing changes until the person applies them, and applying can be undone.
/// Settings that follow personal taste (controls, what the device does when hot) and the audio buffer are never suggested.
enum RecommendedSettings {
    /// The settings a suggestion can cover. nil = not known.
    struct Values: Equatable {
        var launch: String?            // "steam" or "direct"
        var power: String?             // performance, balanced, saver
        var swapMB: Int?
        var swapCoverage: String?      // "", "blocks", "wide", "broad"
        var vramMB: Int?
        var preciseMath: Bool?
        var desktopDisplay: Bool?
    }

    struct Change: Identifiable, Equatable {
        let key: String
        let title: String
        let from: String
        let to: String
        let count: Int
        var id: String { key }
    }

    /// At least this many reports, and more than half of them agreeing on a setting, before it is suggested.
    static let minReports = 2

    static func changes(recommended: Values, counts: [String: Int], reports: Int, current: Values, steamGame: Bool) -> [Change] {
        guard reports >= minReports else { return [] }
        func agreed(_ key: String) -> Int? { counts[key].flatMap { $0 * 2 > reports ? $0 : nil } }
        var out: [Change] = []
        func add<T: Equatable>(_ key: String, _ title: String, _ rec: T?, _ cur: T?, _ text: (T) -> String) {
            guard let rec, let count = agreed(key), rec != cur else { return }
            out.append(Change(key: key, title: title, from: cur.map(text) ?? "not set", to: text(rec), count: count))
        }
        if steamGame { add("launch", "Start", recommended.launch, current.launch) { $0 == "steam" ? "Through Steam" : "Run directly" } }
        add("power", "Power mode", recommended.power, current.power) { $0 == "performance" ? "Performance" : $0 == "saver" ? "Battery saver" : "Balanced" }
        add("swapMB", "Swap", recommended.swapMB, current.swapMB) { $0 <= 0 ? "Off" : "\($0 / 1024 >= 1 && $0 % 1024 == 0 ? "\($0 / 1024) GB" : "\($0) MB")" }
        if (recommended.swapMB ?? current.swapMB ?? 0) > 0 {
            add("swapCoverage", "Swap covers", recommended.swapCoverage, current.swapCoverage) { $0.isEmpty ? "Large (8 MB+)" : $0 == "blocks" ? "All 1 MB+" : $0 == "broad" ? "Broad" : "1 MB+ and overflow" }
        }
        add("vramMB", "Video memory", recommended.vramMB, current.vramMB) { $0 <= 0 ? "Automatic" : "\($0) MB" }
        add("preciseMath", "Precise shader math", recommended.preciseMath, current.preciseMath) { $0 ? "On" : "Off" }
        add("desktopDisplay", "Wine desktop display", recommended.desktopDisplay, current.desktopDisplay) { $0 ? "On" : "Off" }
        return out
    }

    /// What applying changed, so it can be undone: the game's own overrides and how it starts, as they were.
    struct Undo: Codable, Equatable {
        var settings: GameSettings?
        var launchDirect: Bool?
    }

    /// PowerMode's raw values (performance, balanced, saver); the app checks this against the enum.
    static func powerRaw(_ name: String) -> Int? { ["performance": 0, "balanced": 1, "saver": 2][name] }

    /// Writes the chosen changes into the game's own overrides (nothing app-wide), remembering how to undo them.
    static func apply(_ changes: [Change], recommended: Values, to game: inout Game) {
        game.settingsUndo = Undo(settings: game.settings, launchDirect: game.launchDirect)
        var s = game.settings ?? GameSettings()
        for c in changes {
            switch c.key {
            case "power": if let p = recommended.power.flatMap(powerRaw) { s.powerMode = p }
            case "swapMB": if let v = recommended.swapMB { s.swapMB = max(0, v) }
            case "swapCoverage": if let v = recommended.swapCoverage { s.swapCoverage = ["", "blocks", "wide", "broad"].contains(v) ? v : "" }
            case "vramMB": if let v = recommended.vramMB { s.vramMB = max(0, v) }
            case "preciseMath": if let v = recommended.preciseMath { s.preciseMath = v }
            case "desktopDisplay": if let v = recommended.desktopDisplay { s.dockDesktop = v }
            case "launch": if let v = recommended.launch { game.launchDirect = v == "direct" ? true : nil }
            default: break
            }
        }
        game.settings = s.isEmpty ? nil : s
    }

    static func undo(_ game: inout Game) {
        guard let u = game.settingsUndo else { return }
        game.settings = u.settings
        game.launchDirect = u.launchDirect
        game.settingsUndo = nil
    }
}
