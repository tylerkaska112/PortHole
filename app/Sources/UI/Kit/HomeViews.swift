// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

// The home screen and its pieces. They take plain values (no app models), so the same views are drawn by the app and by the simulator preview.

enum ArtKind { case header, hero }

/// How a view asks for a game's picture. The app plugs in Steam's artwork; the default has none.
typealias ArtLoader = @Sendable (UUID, ArtKind) async -> UIImage?
private struct ArtLoaderKey: EnvironmentKey { static let defaultValue: ArtLoader = { _, _ in nil } }
extension EnvironmentValues { var artLoader: ArtLoader { get { self[ArtLoaderKey.self] } set { self[ArtLoaderKey.self] = newValue } } }

struct BadgeData: Equatable {
    var symbol: String
    var text: String
    var tint: Color
}

/// How well a game works with a controller, as Steam lists it.
enum ControllerLevel: String, Equatable {
    case full, partial
    var title: String { self == .full ? "Full controller support" : "Partial controller support" }
    /// What fits on a small tile.
    var short: String { self == .full ? "FULL" : "PARTIAL" }
    /// What the badge means, in plain words (shown when it is tapped on a game's page).
    var explanation: String {
        switch self {
        case .full:
            return "Steam lists this game as designed to be played with a controller from start to finish: the menus, the launcher and the game itself.\n\nPlug in or connect a controller and it should work without the touch screen or a keyboard."
        case .partial:
            return "Steam lists this game as playable with a controller, but not completely. Some parts still expect a keyboard and mouse, usually menus, a launcher, text entry or certain actions, so the game may ask you to switch.\n\nOn Porthole you can still reach those parts: open the game's page, then Controls and key binds, to put keys on controller buttons or show the on-screen controls for the parts the controller cannot do."
        }
    }
}

/// A controller badge that says which kind it is without reading closely: FULL is a solid green capsule, PARTIAL is amber and outlined with dashes.
struct ControllerPill: View {
    let level: ControllerLevel
    var compact = false
    /// Just the controller symbol, in the badge's colour: for a tile that has stepped back and is small.
    var iconOnly = false

    var body: some View {
        let full = level == .full
        let tint = full ? Theme.good : Theme.warn
        HStack(spacing: 5) {
            Image(systemName: "gamecontroller.fill").font(.system(size: compact ? 11 : 13, weight: .bold))
            if !iconOnly {
                Text(compact ? level.short : level.title)
                    .font(.system(size: compact ? 10 : 13, weight: compact ? .heavy : .bold)).tracking(compact ? 0.6 : 0).lineLimit(1).fixedSize()
            }
        }
        .foregroundStyle(full ? Color.black.opacity(0.85) : tint)
        .padding(.horizontal, compact ? 8 : 11).padding(.vertical, compact ? 4 : 6)
        .background(full ? AnyShapeStyle(tint) : AnyShapeStyle(Color.black.opacity(0.6)), in: Capsule())
        .overlay { if !full { Capsule().strokeBorder(tint, style: StrokeStyle(lineWidth: 1.4, dash: [4, 3])) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(level.title)
    }
}

/// The controller badge on a game's own page: pressing it explains what it means.
struct ControllerPillButton: View {
    let level: ControllerLevel
    @State private var shown = false
    @State private var scope = FocusScope()

    var body: some View {
        Button { shown = true } label: { ControllerPill(level: level) }
            .buttonStyle(.plain)
            .focusTarget("controller-badge", radius: 16, scale: 1.08) { shown = true }
            .accessibilityHint("Explains what this means")
            .sheet(isPresented: $shown) { InfoPopover(title: level.title, text: level.explanation, scope: scope) { shown = false } }
    }
}

struct GameCardData: Identifiable, Equatable {
    let id: UUID
    var name: String
    var subtitle: String
    var launchChip: String?          // "Steam" / "Direct"
    var store: GameStore?            // the launcher the game was downloaded from (its badge sits on the picture)
    var badge: BadgeData?
    var controller: ControllerLevel?
}

struct NoticeData: Identifiable, Equatable {
    let id: String
    var symbol: String
    var title: String
    var detail: String?              // shown in the (i) pop-up
    var tint: Color = Theme.accent
    var actionTitle: String?
    var spinner = false
    /// Set for a chip the person may hide (a small x appears on it). The key says which one, so a new one of the same kind (a newer update) shows again.
    var dismissKey: String?
}

/// A game's picture, with a colourful placeholder (made from its name) until the artwork arrives.
struct GameArtView: View {
    let id: UUID
    let name: String
    var kind: ArtKind = .header
    /// Writes the game's name on the colourful placeholder, for a tile whose name is not shown anywhere else.
    var titled = false
    /// No placeholder icon or name while the picture loads: for a backdrop, where a plain gradient is better than a controller symbol.
    var plain = false
    @Environment(\.artLoader) private var loader
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Placeholder(name: name, titled: titled, plain: plain)
            if let image { Image(uiImage: image).resizable().scaledToFill().transition(.opacity) }
        }
        .clipped()
        .animation(.easeOut(duration: 0.3), value: image == nil)
        .task(id: id) { image = nil; image = await loader(id, kind) }
        .accessibilityHidden(true)
    }

    private struct Placeholder: View {
        let name: String
        let titled: Bool
        let plain: Bool
        var body: some View {
            let hue = Double(abs(name.hashValue) % 360) / 360
            ZStack {
                LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.42), Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if plain {
                    EmptyView()
                } else if titled {
                    Text(name).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.7).padding(14)
                } else {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 34)).foregroundStyle(.white.opacity(0.35))
                }
            }
        }
    }
}

/// One game on the shelf: just its picture (the name is written big above the shelf when it is the chosen one), and the glow when selected.
struct GameTile: View {
    let game: GameCardData
    var width: CGFloat = 230
    /// How much the glow ring grows when selected. Smaller when the tile itself already grows (a controller is in use).
    var focusScale: CGFloat = 1.12
    /// A tile that has stepped back: fewer words on its badges.
    var small = false
    var play: (() -> Void)?
    var onFocus: (() -> Void)?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Color.clear.aspectRatio(460.0 / 215.0, contentMode: .fit)
                .overlay { GameArtView(id: game.id, name: game.name, titled: true) }
                .overlay(alignment: .topLeading) { if let badge = game.badge { BadgePill(badge: badge).padding(8) } }
                .overlay(alignment: .bottomTrailing) { if let store = game.store { StoreCorner(store: store, size: small ? 20 : 26).padding(8) } }
                .overlay(alignment: .bottomLeading) { if let level = game.controller { ControllerPill(level: level, compact: true, iconOnly: small).padding(8) } }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(width: width)
        .focusTarget(game.id, radius: 16, scale: focusScale, secondary: play, onFocus: onFocus, action: open)
        .accessibilityLabel(game.name)
    }
}

struct BadgePill: View {
    let badge: BadgeData
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: badge.symbol).font(.caption2.weight(.bold))
            Text(badge.text).font(.caption2.weight(.bold)).lineLimit(1).fixedSize()
        }
        .foregroundStyle(badge.tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(badge.tint.opacity(0.5), lineWidth: 1))
    }
}

/// The chosen game, written large over its artwork: name, a line about it, and Play right there.
struct HeroInfo: View {
    let game: GameCardData
    var mostRecent = true
    let play: () -> Void
    let open: () -> Void
    var playing = false
    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        VStack(alignment: .leading, spacing: vSize == .compact ? 10 : 14) {
            VStack(alignment: .leading, spacing: vSize == .compact ? 6 : 8) {
                if vSize != .compact { Text(mostRecent ? "CONTINUE PLAYING" : "IN YOUR LIBRARY").font(.caption.weight(.heavy)).tracking(1.5).foregroundStyle(Theme.accent) }
                Text(game.name).font(.system(size: vSize == .compact ? 28 : 40, weight: .heavy, design: .rounded)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                FlowLayout(spacing: 8) {
                    if let store = game.store { StoreChip(store: store) }
                    // The store chip already says "Steam"; this one is only for "Direct" (a game that skips its launcher).
                    if let chip = game.launchChip, !(game.store != nil && chip == "Steam") { GlowChip(text: chip, symbol: chip == "Steam" ? "shield.checkered" : "play.fill", tint: .white) }
                    if let badge = game.badge { BadgePill(badge: badge) }
                    if let level = game.controller { ControllerPill(level: level) }
                    Text(game.subtitle).font(.footnote).foregroundStyle(.white.opacity(0.8))
                }
            }
            .id(game.id)
            .transition(.opacity.combined(with: .offset(y: 8)))
            HStack(spacing: 12) {
                PillButton(id: "hero-play", title: playing ? "Preparing" : "Play", symbol: "play.fill", style: .primary, enabled: !playing, action: play)
                PillButton(id: "hero-open", title: "Details", symbol: "slider.horizontal.3", action: open)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .animation(.easeInOut(duration: 0.3), value: game.id)
    }
}

/// Behind the home screen: the chosen game's artwork, dimmed and faded into the background, changing as the selection moves along the shelf.
struct HomeBackdrop: View {
    let game: GameCardData?
    var height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if let game {
                Color.clear.overlay { GameArtView(id: game.id, name: game.name, kind: .hero, plain: true).opacity(0.85) }
                    .clipped()
                    .id(game.id)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .overlay { LinearGradient(colors: [Theme.backgroundBottom.opacity(0.88), Theme.backgroundBottom.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing) }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.45), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.5), value: game?.id)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// A line of things that need attention, as short chips. Details live behind the (i).
struct NoticeStrip: View {
    let notices: [NoticeData]
    let act: (NoticeData) -> Void
    var dismiss: ((NoticeData) -> Void)?
    /// Shorter chips, for a phone held sideways where every point of height counts.
    var compact = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(notices) { n in
                    HStack(spacing: 0) {
                        Button { act(n) } label: {
                            HStack(spacing: 8) {
                                if n.spinner { ProgressView().controlSize(.small).tint(n.tint) } else { Image(systemName: n.symbol).font(.subheadline.weight(.bold)).foregroundStyle(n.tint) }
                                Text(n.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                                if let action = n.actionTitle { Text(action).font(.caption.weight(.heavy)).foregroundStyle(Theme.onAccent).padding(.horizontal, 9).padding(.vertical, 3).background(n.tint, in: Capsule()) }
                            }
                            .padding(.leading, 14).padding(.trailing, n.detail == nil ? 14 : 4).padding(.vertical, compact ? 4 : 8)
                            .frame(minHeight: compact ? 40 : 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusTarget("notice-\(n.id)", radius: 22, scale: 1.04) { act(n) }
                        if let detail = n.detail { InfoButton(id: "notice-info-\(n.id)", title: n.title, text: detail) }
                        if n.dismissKey != nil, let dismiss {
                            Button { dismiss(n) } label: {
                                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textDim)
                                    .frame(width: compact ? 40 : 44, height: compact ? 40 : 44).contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .focusTarget("notice-dismiss-\(n.id)", radius: 22, scale: 1.12) { dismiss(n) }
                            .accessibilityLabel("Hide this")
                        }
                    }
                    .background(Theme.panel, in: Capsule())
                    .overlay(Capsule().strokeBorder(n.tint.opacity(0.35), lineWidth: 1))
                }
            }
            .padding(.vertical, compact ? 2 : 6).padding(.horizontal, 2)
        }
    }
}

/// The last tile on the shelf: add a game.
struct AddGameTile: View {
    var width: CGFloat = 230
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Color.clear.aspectRatio(460.0 / 215.0, contentMode: .fit)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.accent)
                        Text("Add a game").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                    }
                }
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])))
        }
        .buttonStyle(.plain)
        .frame(width: width)
        .focusTarget("add-game", radius: 16, scale: 1.12, action: action)
        .accessibilityLabel("Add a game")
    }
}

/// The home screen: the chosen game's artwork across the back, its name and Play in front, and one shelf of games along the bottom. Moving along the shelf changes the chosen game.
struct HomeView: View {
    let notices: [NoticeData]
    let games: [GameCardData]
    var featuredPlaying = false
    let act: (NoticeData) -> Void
    var dismiss: ((NoticeData) -> Void)?
    let open: (GameCardData) -> Void
    let play: (GameCardData) -> Void
    let add: () -> Void
    var menu: ((GameCardData) -> AnyView)?
    /// Draws the controller layout (wide chosen tile) without a controller: for the simulator preview.
    var forceControllerLayout = false
    @State private var shownID: UUID?
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    private var shown: GameCardData? { games.first { $0.id == shownID } ?? games.first }

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = hSize == .regular ? 32 : 16
            let sideways = vSize == .compact   // a phone held sideways: everything has to fit in about 350 points of height
            let tileWidth: CGFloat = sideways ? min(190, geo.size.width / 4.4) : geo.size.width > 900 ? 270 : hSize == .regular ? 230 : 160
            ZStack {
                HomeBackdrop(game: shown, height: geo.size.height * (geo.size.height > geo.size.width ? 0.72 : 0.8))
                // Not a scroll view: the page is sized to the screen and never moves up or down. Only the row of games scrolls, sideways.
                VStack(alignment: .leading, spacing: sideways ? 8 : 20) {
                    if !notices.isEmpty { NoticeStrip(notices: notices, act: act, dismiss: dismiss, compact: sideways).padding(.horizontal, side - 2) }
                    Spacer(minLength: 0)
                    if let shown {
                        HeroInfo(game: shown, mostRecent: shown.id == games.first?.id, play: { play(shown) }, open: { open(shown) }, playing: featuredPlaying && shown.id == games.first?.id)
                            .padding(.horizontal, side)
                        shelf(tileWidth: tileWidth, side: side, sideways: sideways)
                    } else {
                        EmptyHome(add: add).padding(.horizontal, side)
                    }
                }
                .padding(.vertical, sideways ? 4 : 12)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    /// With a controller the chosen game is wide and the others step back, like Steam's Big Picture shelf; with touch every tile is the same size.
    private func shelf(tileWidth: CGFloat, side: CGFloat, sideways: Bool) -> some View {
        let pad = forceControllerLayout || ControllerInput.shared.connected
        let chosen = shown?.id
        @ViewBuilder func tiles() -> some View {
            ForEach(games) { game in
                GameTile(game: game, width: pad ? (game.id == chosen ? tileWidth * 1.3 : tileWidth * 0.78) : tileWidth, focusScale: pad ? 1.03 : 1.12, small: pad && game.id != chosen,
                         play: { play(game) }, onFocus: { shownID = game.id }) { open(game) }
                    .contextMenu { if let menu { menu(game) } }
            }
            AddGameTile(width: pad ? tileWidth * 0.78 : tileWidth, action: add)
        }
        return FocusScroll(axes: .horizontal) {
            // A big library is built as it scrolls into view; a normal one is built whole, so the D-pad always finds its neighbour.
            Group {
                if games.count > 24 { LazyHStack(spacing: 14) { tiles() } } else { HStack(spacing: 14) { tiles() } }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: shownID)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: pad)
            .padding(.horizontal, side).padding(.vertical, sideways ? 14 : 26)
        }
        .scrollClipDisabled()
    }
}

struct EmptyHome: View {
    let add: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "gamecontroller.fill").font(.system(size: 54)).foregroundStyle(Theme.accentGradient).shadow(color: Theme.accent.opacity(0.6), radius: 18)
            Text("Add your first game").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
            PillButton(id: "empty-add", title: "Add a game", symbol: "plus", style: .primary, action: add)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .panel(radius: 24)
    }
}
