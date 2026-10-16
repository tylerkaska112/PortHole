// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
// Run: app/Tests/Discovery/run.sh   (compiles GameDiscovery.swift for the Mac and checks it against realistic game folders)
import Foundation

var failures = 0
func check(_ ok: Bool, _ message: String) { if ok { print("ok   \(message)") } else { print("FAIL \(message)"); failures += 1 } }
func f(_ path: String, _ mb: Double, _ bits: Int? = 64) -> ProgramFile { ProgramFile(path: path, size: Int64(mb * 1_048_576), bits: bits) }

// Factorio: the game, a few tools, an uninstaller.
do {
    let files = [f(#"C:\Factorio_2.0.77\bin\x64\factorio.exe"#, 38), f(#"C:\Factorio_2.0.77\unins000.exe"#, 1.2, 32), f(#"C:\Factorio_2.0.77\bin\x64\crashpad_handler.exe"#, 1)]
    let games = GameDiscovery.discover(files)
    check(games.count == 1 && games[0].name == "Factorio 2.0.77", "one game, named from its folder (\(games.map(\.name)))")
    check(games[0].best?.fileName == "factorio.exe", "Factorio: the best program is factorio.exe")
    check(games[0].others.allSatisfy { $0.kind == .tool }, "the uninstaller and crash handler are tools")
}

// Unreal: a tiny starter at the root, the real program deep inside.
do {
    let root = #"C:\Games\Tiny Wars"#
    let files = [f(root + #"\TinyWars.exe"#, 0.4), f(root + #"\TinyWars\Binaries\Win64\TinyWars-Win64-Shipping.exe"#, 240),
                 f(root + #"\Engine\Extras\Redist\en-us\UE4PrereqSetup_x64.exe"#, 40)]
    let game = GameDiscovery.discover(files)[0]
    check(game.name == "Tiny Wars" && game.root == root, "Unreal: the folder under Games is the game (\(game.root))")
    check(game.best?.fileName == "TinyWars-Win64-Shipping.exe", "Unreal: the Shipping program beats the starter (\(game.best?.fileName ?? "nil"))")
    check(game.programs.first { $0.fileName.contains("Prereq") }?.kind == .tool, "Unreal: the prerequisites installer is a tool")
}

// Unity: the game, a crash handler, a bundled redistributable that is BIGGER than the game.
do {
    let root = #"C:\Program Files (x86)\Steam\steamapps\common\Schedule I"#
    let files = [f(root + #"\Schedule I.exe"#, 0.6), f(root + #"\UnityCrashHandler64.exe"#, 1.3), f(root + #"\_CommonRedist\vcredist\2019\vc_redist.x64.exe"#, 14.5)]
    let game = GameDiscovery.discover(files)[0]
    check(game.root == root && game.name == "Schedule I", "Steam library: the folder under steamapps\\common is the game (\(game.name))")
    check(game.best?.fileName == "Schedule I.exe", "Unity: the game beats a bigger redistributable (\(game.best?.fileName ?? "nil"))")
}

// A launcher next to the game: the game is preferred.
do {
    let root = #"C:\Games\Space Trader"#
    let files = [f(root + #"\SpaceTraderLauncher.exe"#, 5), f(root + #"\bin\SpaceTrader.exe"#, 60)]
    check(GameDiscovery.discover(files)[0].best?.fileName == "SpaceTrader.exe", "a launcher ranks below the game")
}

// Only installers: no game offered.
do {
    let files = [f(#"C:\Games\Broken\setup.exe"#, 80), f(#"C:\Games\Broken\unins000.exe"#, 1)]
    check(GameDiscovery.discover(files).isEmpty, "a folder with only installers is not offered as a game")
}

// A folder that has only a launcher is still offered (it may be how the game starts).
do {
    let files = [f(#"C:\Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe"#, 3, 32)]
    let games = GameDiscovery.discover(files)
    check(games.count == 1 && games[0].best?.fileName == "EpicGamesLauncher.exe", "the Epic launcher is offered (\(games.map(\.name)))")
}

// System and client folders are never games.
do {
    let files = [f(#"C:\windows\system32\notepad.exe"#, 1), f(#"C:\users\mobile\AppData\x.exe"#, 1), f(#"C:\Program Files (x86)\Steam\steam.exe"#, 4, 32),
                 f(#"C:\Program Files\Common Files\thing\helper.exe"#, 1), f(#"C:\Installers\Setup_Foo.exe"#, 50)]
    check(GameDiscovery.discover(files).isEmpty, "Windows, the Steam client, Common Files and Installers are not games")
}

// Two folders, sorted by name; the same game's programs are grouped together.
do {
    let files = [f(#"C:\Zeta\zeta.exe"#, 5), f(#"C:\Alpha\bin\alpha.exe"#, 5), f(#"C:\Alpha\tools\editor.exe"#, 5)]
    let games = GameDiscovery.discover(files)
    check(games.map(\.name) == ["Alpha", "Zeta"] && games[0].programs.count == 2, "grouped by folder and sorted (\(games.map(\.name)))")
    check(games[0].best?.fileName == "alpha.exe", "the program named like its folder wins over an extra tool-like program")
}

// Duplicates in different case are one program.
do {
    let files = [f(#"C:\Games\Dup\dup.exe"#, 5), f(#"C:\Games\Dup\DUP.EXE"#, 5)]
    check(GameDiscovery.discover(files)[0].programs.count == 1, "the same path in two cases is listed once")
}

check(GameDiscovery.relativePath(#"C:\Games\Foo\bin\x64\foo.exe"#, root: #"C:\Games\Foo"#) == #"bin\x64\foo.exe"#, "relative paths are relative to the game folder")
check(GameDiscovery.tidy("Factorio_2.0.77") == "Factorio 2.0.77", "folder names are tidied")

print(failures == 0 ? "ALL GOOD" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
