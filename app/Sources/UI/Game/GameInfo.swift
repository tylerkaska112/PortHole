// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Small facts about a game, worked out from its files.
enum GameInfo {
    static func duration(_ seconds: Double) -> String {
        let m = Int(seconds / 60)
        if m < 1 { return seconds > 0 ? "Under a minute" : "None yet" }
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }

    static func coverageName(_ v: String) -> String { v == "blocks" ? "All 1 MB+" : v == "wide" ? "1 MB+ and overflow" : v == "broad" ? "Broad" : "Large (8 MB+)" }

    /// Bytes under the game's install folder (a Steam game's folder, else the top-level folder it lives in), or nil when the folder cannot be found.
    static func folderBytes(for g: Game) async -> Int64? {
        await Task.detached(priority: .utility) { () -> Int64? in
            let parts = g.exe.split(separator: "\\").map(String.init)
            var rel = parts.dropLast().joined(separator: "\\")
            if let i = parts.firstIndex(where: { $0.lowercased() == "common" }), i + 1 < parts.count - 1 { rel = parts[0...(i + 1)].joined(separator: "\\") }
            else if parts.count >= 3 { rel = parts[0...1].joined(separator: "\\") }
            guard let url = AppModel.unixURL(forWindows: rel + "\\x")?.deletingLastPathComponent() else { return nil }
            guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return nil }
            var total: Int64 = 0
            for case let f as URL in walker {
                if let v = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]), v.isRegularFile == true { total += Int64(v.totalFileAllocatedSize ?? 0) }
            }
            return total
        }.value
    }

    /// The same as text, or "Unknown".
    static func folderSize(for g: Game) async -> String {
        guard let bytes = await folderBytes(for: g) else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
