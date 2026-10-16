// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

/// A game's picture: Steam's artwork when we can find it, a quiet placeholder until then. Looks the game up once and remembers the answer.
struct GameArt: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var image: UIImage?

    private var symbol: String { game.name.lowercased().contains("factorio") ? "gearshape.2.fill" : "gamecontroller.fill" }

    var body: some View {
        ZStack {
            Theme.panelHigh
            Image(systemName: symbol).font(.system(size: 36, weight: .regular)).foregroundStyle(Theme.textDim.opacity(0.6))
            if let image { Image(uiImage: image).resizable().scaledToFill().transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.25), value: image == nil)
        .task(id: "\(game.id)-\(game.steamAppID ?? -1)") { image = nil; await load() }
        .accessibilityHidden(true)
    }

    private func load() async {
        var id = game.steamAppID
        if id == nil {
            id = await SteamArt.shared.appID(name: game.name, exe: game.exe) ?? 0
            model.setSteamAppID(id, for: game)
        }
        guard let id, id > 0 else { return }
        image = await SteamArt.shared.image(appID: id)
    }
}
