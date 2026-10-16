// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Valve's own client, when it runs inside Porthole's Wine, keeps its own saved sign-in on disk: login tokens in local.vdf (ConnectCache), the account and
/// display names in loginusers.vdf, old-style Steam Guard files (ssfn*), and web cookies. Porthole hands the client a fresh token for every game it starts, so
/// none of that is needed afterwards, and it sits in a folder that Windows programs in the app (and the Files app, and device backups) can reach. It is
/// removed when a Steam session ends and when the app starts, and the folders are kept out of backups.
enum SteamClientTraces {
    static func scrub() {
        let fm = FileManager.default
        let drive = AppModel.driveC
        var removed = 0

        // Per Windows user: AppData\Local\Steam
        let users = drive.appendingPathComponent("users", isDirectory: true)
        for name in (try? fm.contentsOfDirectory(atPath: users.path)) ?? [] {
            let steam = users.appendingPathComponent("\(name)/AppData/Local/Steam", isDirectory: true)
            guard fm.fileExists(atPath: steam.path) else { continue }
            removed += stripConnectCache(steam.appendingPathComponent("local.vdf"))
            for cache in ["htmlcache", "html cache"] {
                let url = steam.appendingPathComponent(cache)
                if fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url); removed += 1 }
            }
            keepOutOfBackups(steam)
        }

        // The client's own folder: config\loginusers.vdf and the ssfn* sentry files.
        if let root = AppModel.unixURL(forWindows: SteamRuntimeFiles.windowsRoot) {
            let login = root.appendingPathComponent("config/loginusers.vdf")
            if fm.fileExists(atPath: login.path) { try? fm.removeItem(at: login); removed += 1 }
            for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where name.lowercased().hasPrefix("ssfn") {
                try? fm.removeItem(at: root.appendingPathComponent(name)); removed += 1
            }
            keepOutOfBackups(root.appendingPathComponent("config", isDirectory: true))
        }
        if removed > 0 { LogStore.shared.log("[steam-client] removed \(removed) saved sign-in item(s) of Valve's client") }
    }

    private static func keepOutOfBackups(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = url
        try? target.setResourceValues(values)
    }

    /// Takes the ConnectCache block (the saved login tokens) out of a Valve KeyValues file and keeps the rest. Returns 1 when something was removed.
    private static func stripConnectCache(_ url: URL) -> Int {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return 0 }
        guard text.range(of: "\"ConnectCache\"", options: .caseInsensitive) != nil else { return 0 }
        var out: [Substring] = []
        var depth = 0, skipping = false, pending = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !skipping, trimmed.lowercased().hasPrefix("\"connectcache\"") { skipping = true; pending = true; depth = 0; continue }
            if skipping {
                if trimmed == "{" { depth += 1; pending = false }
                else if trimmed == "}" { depth -= 1; if depth <= 0 && !pending { skipping = false } }
                continue
            }
            out.append(line)
        }
        guard !skipping else { return 0 }          // an unexpected shape: leave the file as it is
        guard (try? out.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)) != nil else { return 0 }
        return 1
    }
}
