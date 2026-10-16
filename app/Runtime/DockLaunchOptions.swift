// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2026 125hz
// Madeira Converter Exception: see LICENSE-EXCEPTION.md

import Foundation

/// A Steam game's launch options, the way Valve's client keeps them: `LaunchOptions` in the game's block of
/// `userdata/<account>/config/localconfig.vdf` (Software > Valve > Steam > apps > <appid>). The Dock starts Valve's own client, which reads
/// them from there when it launches the game and adds them to the game's command line, so Porthole's "Launch options" row only has to put the
/// text there before the client starts (no session runs then, so the file is not in use). Text edit, not a rewrite: every other line stays.
enum DockLaunchOptions {
    /// Quotes and backslashes escaped the way Valve's text format wants.
    static func escape(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }

    private static func tokens(_ line: String) -> [String] {
        var out: [String] = [], cur = "", inQuote = false, escaped = false
        for ch in line {
            if inQuote {
                if escaped { cur.append(ch); escaped = false }
                else if ch == "\\" { escaped = true; cur.append(ch) }
                else if ch == "\"" { out.append(cur); cur = ""; inQuote = false }
                else { cur.append(ch) }
            } else if ch == "\"" { inQuote = true }
        }
        return out
    }

    /// `text` with LaunchOptions of app `appID` set to `options`, or nil when nothing needs changing (already that value, or the file has no
    /// `apps` block to put it in). An empty `options` removes the line.
    static func setting(_ options: String, appID: Int, in text: String) -> String? {
        let path = ["userlocalconfigstore", "software", "valve", "steam", "apps"]
        let eol = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var stack: [String] = []
        var appsOpen: Int?          // index of the `{` line of the apps block
        var appOpen: Int?, appClose: Int?
        var optionLine: Int?
        var depthOfApps = 0
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            let toks = tokens(trimmed)
            if trimmed == "{" { i += 1; continue }
            if trimmed == "}" {
                if let a = appOpen, appClose == nil, stack.count == depthOfApps + 1 { appClose = i; _ = a }
                if !stack.isEmpty { stack.removeLast() }
                i += 1; continue
            }
            if toks.count == 1, i + 1 < lines.count, lines[i + 1].trimmingCharacters(in: .whitespaces) == "{" {
                stack.append(toks[0].lowercased())
                if stack.count == path.count, stack == path { appsOpen = i + 1; depthOfApps = stack.count }
                if stack.count == path.count + 1, stack.dropLast() == path[...], toks[0] == String(appID), appsOpen != nil { appOpen = i + 1 }
                i += 2; continue
            }
            if toks.count >= 2, appOpen != nil, appClose == nil, stack.count == path.count + 1, toks[0].lowercased() == "launchoptions" { optionLine = i }
            i += 1
        }
        guard let apps = appsOpen else { return nil }
        let value = escape(options)
        if let line = optionLine {
            let indent = String(lines[line].prefix(while: { $0 == "\t" || $0 == " " }))
            if options.isEmpty { lines.remove(at: line) }
            else {
                let new = "\(indent)\"LaunchOptions\"\t\t\"\(value)\""
                if lines[line] == new { return nil }
                lines[line] = new
            }
        } else if let open = appOpen {
            if options.isEmpty { return nil }
            let indent = String(lines[open].prefix(while: { $0 == "\t" || $0 == " " })) + "\t"
            lines.insert("\(indent)\"LaunchOptions\"\t\t\"\(value)\"", at: open + 1)
        } else {
            if options.isEmpty { return nil }
            let base = String(lines[apps].prefix(while: { $0 == "\t" || $0 == " " }))
            let block = ["\(base)\t\"\(appID)\"", "\(base)\t{", "\(base)\t\t\"LaunchOptions\"\t\t\"\(value)\"", "\(base)\t}"]
            lines.insert(contentsOf: block, at: apps + 1)
        }
        return lines.joined(separator: eol)
    }

    /// Writes `options` into every account's localconfig.vdf under the prefix's Steam folder. Returns how many files changed.
    @discardableResult
    static func apply(_ options: String, appID: Int, drive: URL, log: (String) -> Void = { _ in }) -> Int {
        let trimmed = options.trimmingCharacters(in: .whitespacesAndNewlines)
        let userdata = drive.appendingPathComponent("Program Files (x86)/Steam/userdata", isDirectory: true)
        guard let accounts = try? FileManager.default.contentsOfDirectory(atPath: userdata.path) else { return 0 }
        var changed = 0
        for account in accounts where account.allSatisfy({ $0.isNumber }) {
            let file = userdata.appendingPathComponent(account).appendingPathComponent("config/localconfig.vdf")
            guard let data = try? Data(contentsOf: file), data.count < 8 << 20 else { continue }
            guard let updated = setting(trimmed, appID: appID, in: String(decoding: data, as: UTF8.self)) else { continue }
            do { try Data(updated.utf8).write(to: file, options: .atomic); changed += 1 }
            catch { log("[dock-launch] launch options not written (\(account)): \(error.localizedDescription)") }
        }
        if changed > 0 { log("[dock-launch] launch options for app \(appID): \(trimmed.isEmpty ? "(none)" : trimmed) written to \(changed) account file(s)") }
        return changed
    }
}
