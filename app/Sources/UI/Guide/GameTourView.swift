// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

/// The tour of the first game ever started. It is a normal full screen of the app that comes BEFORE the game: the game does not start until the tour ends, so nothing competes with it
/// for the processor and every touch answers at once. A picture of the game screen shows where the pencil and the keyboard button will be and how the edge swipe works.
struct GameTourView: View {
    /// The game that waits for the tour, or nil when it is shown on request.
    let gameName: String?
    var onFinish: () -> Void

    @State private var index: Int
    @State private var scope = FocusScope()
    @Environment(\.verticalSizeClass) private var vSize

    init(gameName: String?, startAt: Int = 0, onFinish: @escaping () -> Void) {
        self.gameName = gameName; self.onFinish = onFinish
        _index = State(initialValue: startAt)
    }

    private let steps = GuideCatalog.inGame.steps
    private var step: GuideStep { steps[index] }
    private var last: Bool { index >= steps.count - 1 }

    var body: some View {
        ZStack {
            AmbientBackdrop(animated: false)
            VStack(spacing: 0) {
                header
                Group {
                    if index == 3 {
                        // The last step is a list; it has all the room, with its heading above it.
                        VStack(spacing: 14) {
                            Text(step.title).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text)
                            GestureList()
                        }
                    } else if vSize == .compact { HStack(spacing: 28) { picture; text } } else { VStack(spacing: 22) { picture; text } }
                }
                .padding(.horizontal, 28).frame(maxHeight: .infinity)
                controls
            }
            .readableWidth(1000)
        }
        .navScope(scope)
        .onAppear {
            scope.defaultFocus = "tour-next"; scope.focused = "tour-next"
            scope.onBack = { if index > 0 { go(-1) } }
        }
        .preferredColorScheme(Theme.scheme)
    }

    private var header: some View {
        HStack {
            Text(gameName.map { "Before \($0) starts" } ?? "How to play").font(.footnote.weight(.bold)).foregroundStyle(Theme.textDim).textCase(.uppercase).tracking(0.6).lineLimit(1)
            Spacer()
            Text("\(index + 1) of \(steps.count)").font(.footnote.monospacedDigit()).foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 6)
    }

    private var picture: some View { TourMock(step: index) }

    private var text: some View {
        VStack(spacing: 10) {
            IconTile(symbol: step.symbol, size: vSize == .compact ? 44 : 56)
            Text(step.title).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            Text(step.text).font(.body).foregroundStyle(Theme.text.opacity(0.88)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 460).id(index).transition(.opacity)
    }

    private var controls: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                if index > 0 { PillButton(id: "tour-back", title: "Back", symbol: "chevron.left") { go(-1) } }
                PillButton(id: "tour-next", title: last ? (gameName == nil ? "Done" : "Start the game") : "Next", symbol: last ? (gameName == nil ? "checkmark" : "play.fill") : "chevron.right", style: .primary) {
                    if last { onFinish() } else { go(1) }
                }
            }
            HStack(spacing: 6) {
                Button { onFinish() } label: { Text(gameName == nil ? "Close" : "Skip and start").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textDim).padding(.vertical, 10).padding(.horizontal, 14) }
                    .buttonStyle(.plain).focusTarget("tour-skip", radius: 14, scale: 1.04) { onFinish() }
                Button { GuideCenter.shared.enabled = false; onFinish() } label: { Text("Do not show tips").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textDim).padding(.vertical, 10).padding(.horizontal, 14) }
                    .buttonStyle(.plain).focusTarget("tour-off", radius: 14, scale: 1.04) { GuideCenter.shared.enabled = false; onFinish() }
            }
        }
        .padding(.bottom, 14)
    }

    private func go(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.2)) { index = max(0, min(steps.count - 1, index + delta)) }
        scope.focused = "tour-next"
    }
}

/// A picture of the game screen: the pencil and the keyboard button where they will be, with the one the step is about ringed; on the edge step, the swipe and the menu sliding in.
private struct TourMock: View {
    let step: Int
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, panel = w * 0.34
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "mountain.2.fill").font(.system(size: h * 0.5)).foregroundStyle(.white.opacity(0.06)).frame(width: w, height: h)
                HStack(spacing: 8) {
                    chip("pencil", ringed: step == 0)
                    chip("keyboard", ringed: step == 1)
                }
                .padding(14)
                if step == 2 {
                    // The menu panel sliding in from the right edge, and the arrows that show the finger's way.
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.12).opacity(0.95))
                        .overlay(VStack(alignment: .leading, spacing: 9) { ForEach(0..<4, id: \.self) { _ in Capsule().fill(.white.opacity(0.22)).frame(height: 8) } }.padding(14))
                        .frame(width: panel, height: h - 28)
                        .offset(x: w - panel - 14 + (pulse ? 0 : panel + 24), y: 14)
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in Image(systemName: "chevron.left").font(.system(size: 26, weight: .heavy)).opacity(1 - Double(i) * 0.3) }
                    }
                    .foregroundStyle(.white).position(x: w - 44 - (pulse ? 60 : 0), y: h * 0.5).opacity(pulse ? 0.25 : 1)
                    Capsule().fill(Theme.accent.opacity(0.9)).frame(width: 5, height: 56).position(x: w - 6, y: h * 0.5)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: 520)
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true } }
        .accessibilityHidden(true)
    }

    private func chip(_ symbol: String, ringed: Bool) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            .padding(.vertical, 8).padding(.horizontal, 10)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if ringed {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.accent, lineWidth: 3).padding(-6).scaleEffect(pulse ? 1.12 : 1)
                }
            }
    }
}

/// How touching the game works, one gesture per line.
private struct GestureList: View {
    private let rows: [(String, String, String)] = [
        ("hand.tap.fill", "Tap", "a click"),
        ("hand.draw.fill", "Drag", "holds the left button while you move"),
        ("hand.point.up.fill", "Press and hold, or tap with two fingers", "the right button"),
        ("arrow.up.left.and.arrow.down.right", "Pinch", "the mouse wheel (spread to zoom in)"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 12) {
                    IconTile(symbol: rows[i].0, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rows[i].1).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                        Text(rows[i].2).font(.subheadline).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18).frame(maxWidth: 560, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
