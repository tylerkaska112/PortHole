// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2026 125hz
// Madeira Converter Exception: see LICENSE-EXCEPTION.md

import Foundation

/// Registry entries a program's installer writes, put back when the program's files are on
/// disk but the entries are not. The wineserver keeps the registry in memory and writes it
/// back on a timer and when it stops, so an installer's last registry writes are lost when
/// the app is closed or killed soon after it finishes, while its files and shortcuts stay.
/// The install then looks complete (the desktop icon is there) but anything that detects it
/// through the registry says it is not installed. Far Cry 6: "Unable to detect Ubisoft
/// Connect installation" with Ubisoft Connect fully extracted.
///
/// Only ever adds what is missing; a value that exists, whatever it holds, is left alone.
/// Like the install records, it only runs while no session does (the registry is on disk).
enum DockRegistryRepair {
    struct Repair: Equatable {
        var name: String
        /// A file under drive_c whose presence means the program is installed.
        var marker: String
        /// Which registry file the keys live in.
        var file: String = "system.reg"
        /// Keys under the hive (for HKLM the 32-bit view first, as an installer is a 32-bit program).
        var keys: [String]
        var values: [(name: String, data: String)]
        /// false: only add what is missing. true: also replace a value that holds something else (the value is a location that
        /// has to point at the program that is really there).
        var force: Bool = false
        static func == (a: Repair, b: Repair) -> Bool { a.name == b.name && a.file == b.file }
    }

    static let known: [Repair] = [
        Repair(name: "Ubisoft Connect",
               marker: "Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftGameLauncher.exe",
               keys: ["Software\\Wow6432Node\\Ubisoft\\Launcher", "Software\\Ubisoft\\Launcher"],
               values: [("InstallDir", "C:\\Program Files (x86)\\Ubisoft\\Ubisoft Game Launcher\\")]),
        // Where Steam is. Another program that was run in the same prefix (a game installed outside Steam wrote C:\NIS B...~AG)
        // had overwritten these; Ubisoft Connect, a 32-bit program, reads the 32-bit view, found no Steam there, and downloaded
        // and ran SteamSetup.exe after the login instead of going on. The Dock's Steam is always here.
        Repair(name: "Steam location (32-bit view)",
               marker: "Program Files (x86)/Steam/steam.exe",
               keys: ["Software\\Wow6432Node\\Valve\\Steam"],
               values: [("InstallPath", "C:\\Program Files (x86)\\Steam")], force: true),
        Repair(name: "Steam location (user)",
               marker: "Program Files (x86)/Steam/steam.exe", file: "user.reg",
               keys: ["Software\\Valve\\Steam"],
               values: [("SteamPath", "C:/Program Files (x86)/Steam"), ("SteamExe", "C:/Program Files (x86)/Steam/steam.exe")], force: true),
    ]

    /// Wine's .reg text with the string values added where the key lacks them, and how many were added.
    static func add(keys: [String], values: [(name: String, data: String)], force: Bool = false, in text: String, now: Int) -> (text: String, added: Int) {
        var lines = text.components(separatedBy: "\n")
        var added = 0
        for key in keys {
            let header = "[" + escape(key) + "]"
            for value in values {
                let prefix = "\"" + escape(value.name) + "\"="
                let line = prefix + "\"" + escape(value.data) + "\""
                if let start = lines.firstIndex(where: { $0.lowercased().hasPrefix(header.lowercased() + " ") || $0.lowercased() == header.lowercased() }) {
                    var end = start + 1
                    while end < lines.count, !lines[end].hasPrefix("[") { end += 1 }
                    if let at = (start + 1..<end).first(where: { lines[$0].lowercased().hasPrefix(prefix.lowercased()) }) {
                        if force && lines[at] != line { lines[at] = line; added += 1 }
                        continue
                    }
                    var at = end
                    while at > start + 1, lines[at - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { at -= 1 }
                    lines.insert(line, at: at)
                } else {
                    while let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.removeLast() }
                    lines += ["", header + " \(now)", line, ""]
                }
                added += 1
            }
        }
        return (lines.joined(separator: "\n"), added)
    }

    /// Runs every known repair whose marker file exists. Returns the repairs that changed something.
    @discardableResult
    static func run(drive: URL, prefix: URL, log: (String) -> Void = { _ in }) -> [String] {
        var texts: [String: String] = [:]
        var repaired: [String] = []
        var changedFiles: [String] = []
        for repair in known where FileManager.default.fileExists(atPath: drive.appendingPathComponent(repair.marker).path) {
            if texts[repair.file] == nil {
                guard let data = try? Data(contentsOf: prefix.appendingPathComponent(repair.file)), !data.isEmpty else { continue }   // a prefix not seeded yet
                texts[repair.file] = String(decoding: data, as: UTF8.self)
            }
            let (updated, added) = add(keys: repair.keys, values: repair.values, force: repair.force, in: texts[repair.file]!, now: Int(Date().timeIntervalSince1970))
            guard added > 0 else { continue }
            texts[repair.file] = updated
            repaired.append(repair.name)
            if !changedFiles.contains(repair.file) { changedFiles.append(repair.file) }
            log("[dock-installers] registry repair: \(repair.name): \(added) registry value(s) \(repair.force ? "corrected or added" : "were missing; added")")
        }
        for file in changedFiles {
            let registry = prefix.appendingPathComponent(file)
            let backup = registry.appendingPathExtension("madeira-bak")
            if !FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.copyItem(at: registry, to: backup) }
            do { try Data(texts[file]!.utf8).write(to: registry, options: .atomic) }
            catch { log("[dock-installers] registry repair not written (\(file)): \(error.localizedDescription)"); return [] }
        }
        return repaired
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
