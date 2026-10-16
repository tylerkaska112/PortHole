// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

/// Game details > Program: pick another program of the game's folder to start, without removing the game and adding it again. Only `exe` changes; the game keeps
/// its Steam link (steamAppID, dockAppID), compatibility record, settings, controls and play time.
struct ChangeProgramSheet: View {
    let game: Game
    let scope: FocusScope
    let close: () -> Void
    @EnvironmentObject var model: AppModel
    @State private var programs: [GameProgram]?
    @State private var manual = ""

    /// The game's folder: its game root when it has one (a Steam game's folder), otherwise the folder the program sits in.
    private var rootPath: String {
        if let root = GameDiscovery.gameRoot(of: game.exe)?.root { return root }
        var parts = game.exe.split(separator: "\\").map(String.init)
        if parts.count > 1 { parts.removeLast() }
        return parts.joined(separator: "\\")
    }

    var body: some View {
        GameSubSheet(title: "Choose the program", scope: scope, close: close) {
            SettingsGroup(title: "Now") {
                RowBase(id: "cp-now", symbol: "terminal.fill", title: game.exe.split(separator: "\\").last.map(String.init) ?? game.exe, subtitle: game.exe, action: {}) { EmptyView() }
            }
            if let programs {
                if programs.isEmpty {
                    Text("No programs were found in \(rootPath).").font(.footnote).foregroundStyle(Theme.textDim).padding(.horizontal, 6)
                } else {
                    ProgramChooserView(name: game.name, programs: programs, actionTitle: "Use this program") { pick($0.file.path) }
                }
            } else {
                HStack(spacing: 10) { ProgressView().tint(Theme.accent); Text("Looking in the game\u{2019}s folder\u{2026}").foregroundStyle(Theme.textDim) }.padding(.horizontal, 6)
            }
            SettingsGroup(title: "Somewhere else") {
                TextFieldRow(id: "cp-path", symbol: "pencil", title: "Program", placeholder: #"C:\Games\Foo\foo.exe"#, monospaced: true, text: $manual)
                PillButton(id: "cp-go", title: "Use this path", symbol: "checkmark", style: .primary, enabled: !manual.trimmingCharacters(in: .whitespaces).isEmpty) { pick(manual) }
            }
        }
        .task {
            let root = rootPath
            let drive = AppModel.driveC
            let found = await Task.detached(priority: .userInitiated) { () -> [GameProgram] in
                let folder = AppModel.unixURL(forWindows: root + "\\x")?.deletingLastPathComponent()
                let files = GameDiscovery.scanDrive(drive, under: folder)
                let name = root.split(separator: "\\").last.map(String.init) ?? root
                return GameDiscovery.rank(files, folderName: name, root: root)
            }.value
            programs = found
        }
    }

    private func pick(_ raw: String) {
        var exe = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while exe.contains("\\\\") { exe = exe.replacingOccurrences(of: "\\\\", with: "\\") }
        guard !exe.isEmpty, exe.caseInsensitiveCompare(game.exe) != .orderedSame else { close(); return }
        model.update(game) { $0.exe = exe }
        close()
    }
}
