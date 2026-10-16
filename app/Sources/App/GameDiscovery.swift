// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Finding the game in a folder full of programs.
///
/// A game folder holds dozens of .exe files: the game, its uninstaller, redistributable installers, crash reporters and helper tools. The old import
/// listed every one as a raw Windows path. This ranks them so the likely one is offered first, tools are tucked away, and folders that are already in
/// the library are left out.

struct ProgramFile: Equatable, Sendable {
    var path: String          // Windows path, C:\Games\Foo\bin\foo.exe
    var size: Int64
    var bits: Int?
}

struct GameProgram: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case game, launcher, tool }
    let file: ProgramFile
    let relative: String      // relative to the game's folder: bin\foo.exe
    let kind: Kind
    let score: Double
    var id: String { file.path }
    var fileName: String { file.path.split(separator: "\\").last.map(String.init) ?? file.path }
}

struct DiscoveredGame: Identifiable, Equatable, Sendable {
    let name: String          // folder name, tidied for display
    let root: String          // Windows path of the game's folder
    let programs: [GameProgram]   // best first
    var id: String { root.lowercased() }
    /// The program most likely to start the game (never an installer or tool).
    var best: GameProgram? { programs.first { $0.kind != .tool } }
    var others: [GameProgram] { programs.filter { $0.id != best?.id } }
}

enum GameDiscovery {
    // MARK: Which files are tools

    /// Words in a program's name that mean it is not the game.
    private static let toolWords = [
        "unins", "uninst", "uninstall", "setup", "install", "instmsi", "vcredist", "vc_redist", "redist", "dxsetup", "dxwebsetup", "dotnet", "ndp4", "ndp3",
        "oalinst", "physx", "ue4prereq", "ue5prereq", "prereq", "crashhandler", "crashreport", "crashpad", "bugreport", "errorreporter", "reporter", "helper",
        "updater", "autoupdate", "patcher", "benchmark", "cleanup", "cefsubprocess", "cefprocess", "webhelper", "easyanticheat", "beservice", "bootstrapper",
        "dxwebsetup", "notification_helper", "sendreport", "diagnostic", "configtool", "7z", "ffmpeg"
    ]
    private static let launcherWords = ["launcher", "launch", "config", "settings", "options", "menu"]

    static func isTool(_ fileName: String) -> Bool {
        let name = fileName.lowercased()
        return toolWords.contains { name.contains($0) }
    }

    private static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func words(_ text: String) -> Set<String> {
        let parts = text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init).filter { $0.count >= 3 }
        return Set(parts)
    }

    // MARK: Ranking inside one game folder

    /// Orders the programs in one game's folder, best first. `root` is the folder's Windows path (used to show shorter relative paths).
    static func rank(_ files: [ProgramFile], folderName: String, root: String) -> [GameProgram] {
        var seen = Set<String>()
        let folder = normalized(folderName), folderWords = words(folderName)
        let ranked: [GameProgram] = files.compactMap { file in
            guard seen.insert(file.path.lowercased()).inserted else { return nil }
            let fileName = file.path.split(separator: "\\").last.map(String.init) ?? file.path
            let base = (fileName as NSString).deletingPathExtension
            let name = normalized(base)
            let lower = fileName.lowercased()
            let relative = relativePath(file.path, root: root)
            let depth = max(0, relative.split(separator: "\\").count - 1)

            var score = 0.0
            let kind: GameProgram.Kind
            if isTool(fileName) { kind = .tool; score -= 200 }
            else if launcherWords.contains(where: { lower.contains($0) }) { kind = .launcher; score -= 25 }
            else { kind = .game }

            if !folder.isEmpty {
                if name == folder { score += 60 }
                else if name.count >= 4, folder.count >= 4, name.contains(folder) || folder.contains(name) { score += 40 }
                else if !words(base).isDisjoint(with: folderWords) { score += 20 }
            }
            score += depth == 0 ? 15 : depth == 1 ? 8 : depth == 2 ? 3 : 0
            score += min(40, log10(Double(max(file.size, 1))) * 5)
            if file.bits == 64 { score += 6 }
            if name.hasSuffix("win64shipping") || name.hasSuffix("shipping") { score += 40 }   // Unreal's real program, not its small starter
            return GameProgram(file: file, relative: relative, kind: kind, score: score)
        }
        return ranked.sorted { $0.score != $1.score ? $0.score > $1.score : $0.relative.count < $1.relative.count }
    }

    static func relativePath(_ path: String, root: String) -> String {
        let prefix = root.lowercased().hasSuffix("\\") ? root.lowercased() : root.lowercased() + "\\"
        return path.lowercased().hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    // MARK: Which folder is a game

    /// Folders under drive_c that are Windows itself or the system, never games.
    private static let systemFolders: Set<String> = ["windows", "users", "programdata", "installers", "common files", "windows nt", "internet explorer", "windows media player",
                                                    "windowsapps", "microsoft", "windows mail", "windows photo viewer", "windows defender", "msbuild", "reference assemblies"]

    /// The folder a program belongs to as a game: a Steam game's folder, the first folder under Program Files or Games, or its top-level folder.
    /// Nil for Windows' own files and for the Steam client.
    static func gameRoot(of path: String) -> (root: String, name: String)? {
        var parts = path.split(separator: "\\").map(String.init)
        guard parts.count >= 3, parts[0].lowercased() == "c:" else { return nil }
        parts.removeFirst()                       // "C:"
        let dirs = Array(parts.dropLast())
        guard let top = dirs.first?.lowercased(), !systemFolders.contains(top) else { return nil }
        let lowered = dirs.map { $0.lowercased() }

        func make(_ count: Int) -> (String, String)? {
            guard dirs.count >= count else { return nil }
            let name = dirs[count - 1]
            if systemFolders.contains(name.lowercased()) { return nil }
            return ("C:\\" + dirs[0..<count].joined(separator: "\\"), name)
        }
        if let steamapps = lowered.firstIndex(of: "steamapps"), steamapps + 2 < dirs.count, lowered[steamapps + 1] == "common" {
            return make(steamapps + 3)
        }
        if top.hasPrefix("program files") {
            guard let found = make(2), found.1.lowercased() != "steam" else { return nil }      // the Steam client is not a game
            return found
        }
        if top == "games" || top == "game" { return make(2) }
        return make(1)
    }

    /// Every game folder found among `files`, each with its programs ranked. Folders with nothing but tools are left out.
    static func discover(_ files: [ProgramFile]) -> [DiscoveredGame] {
        var byRoot: [String: (name: String, root: String, files: [ProgramFile])] = [:]
        for file in files {
            guard let (root, name) = gameRoot(of: file.path) else { continue }
            let key = root.lowercased()
            byRoot[key, default: (name, root, [])].files.append(file)
        }
        return byRoot.values.compactMap { entry in
            let programs = rank(entry.files, folderName: entry.name, root: entry.root)
            guard programs.contains(where: { $0.kind != .tool }) else { return nil }
            return DiscoveredGame(name: tidy(entry.name), root: entry.root, programs: programs)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// "Factorio_2.0.77" becomes "Factorio 2.0.77".
    static func tidy(_ folder: String) -> String { folder.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces) }

    // MARK: Reading the disk

    /// All .exe files under drive_c (to seven levels), with their sizes, or only those under `folder` (a place inside drive_c). Skips Windows itself.
    static func scanDrive(_ driveC: URL, under folder: URL? = nil, maxDepth: Int = 7) -> [ProgramFile] {
        let root = driveC.resolvingSymlinksInPath()
        guard let walker = FileManager.default.enumerator(at: (folder ?? driveC).resolvingSymlinksInPath(), includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var found: [ProgramFile] = []
        for case let url as URL in walker {
            let full = url.resolvingSymlinksInPath().path
            guard full.hasPrefix(root.path + "/") else { continue }
            let rel = String(full.dropFirst(root.path.count + 1))
            let comps = rel.split(separator: "/").map { $0.lowercased() }
            if comps.count > maxDepth { walker.skipDescendants(); continue }
            if comps.count == 1, systemFolders.contains(comps[0]) { walker.skipDescendants(); continue }
            guard url.pathExtension.lowercased() == "exe" else { continue }
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            found.append(ProgramFile(path: "C:\\" + rel.split(separator: "/").joined(separator: "\\"), size: size, bits: nil))
        }
        return found
    }
}
