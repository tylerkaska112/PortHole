// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Known problems with particular games, and the small, reversible workaround for each. Applied just before the game starts (see SessionController.start).
/// A workaround here only ever hides a file in that game's own folder; nothing of the game is changed or deleted. docs/GAME_FIXES.md lists them.
enum GameFixes {
    struct Fix: Equatable {
        let steamAppID: Int
        let title: String
        /// Files, relative to the folder the game's program is in, that are set aside (renamed with `disabledSuffix`) before the game starts.
        let hide: [String]
        let why: String
        /// Libraries Wine must refuse to load for this game (`WINEDLLOVERRIDES=name=`). Refused before anything is copied into the emulator's code pool.
        var blockLoading: [String] = []
        /// A program in the same folder to start instead of the one Steam lists (a launcher the game does not need), when the game is started without Steam.
        var directProgram: String? = nil
        /// The game cannot work through Steam's launch (its launcher needs software Porthole does not have), so it always starts directly.
        var alwaysDirect = false
        /// When started without Steam, tell the game its own Steam app id and install folder instead of the fixed placeholder identity the runtime otherwise publishes.
        var ownSteamIdentity = false
        /// A program in the same folder to start NEXT TO Valve's signed-in client instead of asking the client to launch the game (Steam stays up, the program finds it).
        /// For a game whose listed program cannot run here but whose own program can. The Dock host only accepts a .exe inside the app's verified install folder.
        var steamProgram: String? = nil
        /// The game's Chromium helper programs (a launcher's web UI) want a 32 GB address-space pool aligned to 32 GB; this moves the emulator's band out of the
        /// way so they can have one (patch 0105, `pa-pool32-soft`). Only for games that need it: it changes the address-space layout.
        var paPool32 = false

        /// The value for WINEDLLOVERRIDES, e.g. "avrt=;foo=".
        var overridesValue: String { blockLoading.map { $0 + "=" }.joined(separator: ";") }
    }

    static let disabledSuffix = ".porthole-disabled"

    static let known: [Fix] = [
        Fix(steamAppID: 242760, title: "The Forest",
            hide: ["TheForest_Data/Plugins/OVRPlugin.dll", "TheForest_Data/Mono/OVRPlugin.dll"],
            why: "The emulator's code pool (624 MB) only gets space back when a whole emulated process exits. Unity tried to load the Oculus VR plugin six times (it can never load here) at about 28 MB each, and its short-lived threads each load and unload avrt.dll (about 0.5 MB each, hundreds of times), until the pool was full and the game froze.",
            blockLoading: ["avrt"]),
        Fix(steamAppID: 244210, title: "Assetto Corsa",
            hide: [],
            why: "AssettoCorsa.exe, the program Steam lists, is a .NET launcher. Porthole has no .NET (Wine reports \"Wine Mono is not installed\" and the program exits at once), and Steam's own launch hits the same program. The game itself is acs.exe in the same folder, so Porthole starts that directly.",
            directProgram: "acs.exe", alwaysDirect: true, ownSteamIdentity: true),
        Fix(steamAppID: 252490, title: "Rust",
            hide: [],
            why: "Valve's client starts Rust.exe, which starts Easy Anti-Cheat; that does not run here. RustClient.exe is the game itself and plays on servers that do not require Easy Anti-Cheat. Steam's own client stays signed in (so the game's Steam library finds it) and RustClient.exe is started next to it, the way double-clicking it with Steam open does on a PC. Started without Steam at all, the game stalled at 99 % loading.",
            steamProgram: "RustClient.exe"),
        Fix(steamAppID: 1174180, title: "Red Dead Redemption 2",
            hide: [],
            why: "Rockstar's launcher shows its pages with Chromium (SocialClubHelper.exe). Its memory allocator wants a 32 GB address-space pool aligned to 32 GB, which the emulator's band at the top of the address space prevents: every helper stopped at start and the launcher said it timed out loading its content. The band is moved so the pool fits.",
            paPool32: true),
    ]

    static func fix(forSteamAppID id: Int?) -> Fix? {
        guard let id, id > 0 else { return nil }
        return known.first { $0.steamAppID == id }
    }

    /// Sets the fix's files aside inside `folder`. Returns what was done, one line each, for the log. Safe to run on every launch: files already set aside are left alone,
    /// and a file that came back (the game was updated or verified) is set aside again. Paths that would leave `folder` are refused.
    @discardableResult
    static func hide(_ fix: Fix, in folder: URL, fileManager fm: FileManager = .default) -> [String] {
        var done: [String] = []
        let root = folder.standardizedFileURL.path
        for relative in fix.hide {
            let url = folder.appendingPathComponent(relative).standardizedFileURL
            guard url.path.hasPrefix(root + "/") else { done.append("refused \(relative): outside the game folder"); continue }
            guard fm.fileExists(atPath: url.path) else { continue }
            let aside = URL(fileURLWithPath: url.path + disabledSuffix)
            do {
                if fm.fileExists(atPath: aside.path) { try fm.removeItem(at: aside) }
                try fm.moveItem(at: url, to: aside)
                done.append("set aside \(relative)")
            } catch {
                done.append("couldn't set aside \(relative): \(error.localizedDescription)")
            }
        }
        return done
    }

    /// The file called `name` in the same folder as `program`, if it exists (compared ignoring case, as Windows would).
    static func sibling(named name: String, of program: URL, fileManager fm: FileManager = .default) -> URL? {
        let folder = program.deletingLastPathComponent()
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path),
              let hit = names.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        return folder.appendingPathComponent(hit)
    }

    /// `windowsPath` with its last component replaced ("C:\\a\\b.exe" + "c.exe" -> "C:\\a\\c.exe").
    static func windowsPath(replacingLastComponentOf windowsPath: String, with name: String) -> String {
        var parts = windowsPath.split(separator: "\\", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return windowsPath }
        parts[parts.count - 1] = name
        return parts.joined(separator: "\\")
    }

    /// Puts the fix's files back.
    @discardableResult
    static func restore(_ fix: Fix, in folder: URL, fileManager fm: FileManager = .default) -> [String] {
        var done: [String] = []
        for relative in fix.hide {
            let url = folder.appendingPathComponent(relative)
            let aside = URL(fileURLWithPath: url.path + disabledSuffix)
            guard fm.fileExists(atPath: aside.path), !fm.fileExists(atPath: url.path) else { continue }
            do { try fm.moveItem(at: aside, to: url); done.append("restored \(relative)") }
            catch { done.append("couldn't restore \(relative): \(error.localizedDescription)") }
        }
        return done
    }
}
