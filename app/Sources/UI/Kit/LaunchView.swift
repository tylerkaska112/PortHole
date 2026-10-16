// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

struct LaunchStepData: Identifiable, Equatable {
    enum State { case pending, active, done }
    let id: String
    var title: String
    var state: State
}

struct LaunchSettingChip: Identifiable, Equatable {
    var id: String { text }
    var symbol: String
    var text: String
}

struct LaunchData: Equatable {
    var gameID: UUID
    var name: String
    var steps: [LaunchStepData]
    /// What is happening right now, in a few words ("Signing in to Steam").
    var headline: String
    /// Longer detail, shown behind the (i).
    var detail: String?
    var chips: [LaunchSettingChip]
    var failure: String?
    /// False once the game's program is running: it cannot be taken back, so the button becomes "Stop game".
    var cleanCancel = true

    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        let done = Double(steps.filter { $0.state == .done }.count)
        return min(1, (done + (steps.contains { $0.state == .active } ? 0.5 : 0)) / Double(steps.count))
    }
}

/// What the person sees from pressing Play until the game's own window appears.
struct LaunchView: View {
    let data: LaunchData
    /// Owned by whoever shows the screen, so it can take the layer away from the controller when the screen goes.
    let scope: FocusScope
    let cancel: () -> Void
    var showSteam: (() -> Void)?
    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        ZStack {
            background
            GeometryReader { geo in
                let wide = geo.size.width > geo.size.height * 1.05
                Group {
                    if wide {
                        HStack(spacing: 40) {
                            info.frame(maxWidth: .infinity, alignment: .leading)
                            porthole(size: min(geo.size.height * (vSize == .compact ? 0.7 : 0.62), 340))
                        }
                    } else {
                        VStack(spacing: 24) { porthole(size: min(geo.size.width * 0.6, 280)); info }
                    }
                }
                .padding(.horizontal, wide ? 56 : 24).padding(.vertical, vSize == .compact ? 12 : 28)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .navScope(scope)
        .onAppear { scope.onBack = cancel; scope.defaultFocus = "launch-cancel"; scope.focused = "launch-cancel" }
        .preferredColorScheme(.dark)
    }

    // MARK: Pieces

    private var background: some View {
        ZStack {
            Color.black
            Color.clear.overlay { GameArtView(id: data.gameID, name: data.name, kind: .hero).blur(radius: 14).scaleEffect(1.08).opacity(0.9) }.clipped()
            LinearGradient(colors: [.black.opacity(0.88), .black.opacity(0.55), .black.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            RadialGradient(colors: [Theme.accent.opacity(0.18 * max(Theme.glowStrength, 0.4)), .clear], center: .trailing, startRadius: 0, endRadius: 600)
        }
        .ignoresSafeArea()
    }

    private var info: some View {
        let tight = vSize == .compact
        return VStack(alignment: .leading, spacing: tight ? 9 : 16) {
            Text(data.failure == nil ? "STARTING" : "COULDN'T START").font(.caption.weight(.heavy)).tracking(2).foregroundStyle(data.failure == nil ? Theme.accent : Theme.bad)
            Text(data.name).font(.system(size: tight ? 28 : 38, weight: .heavy, design: .rounded)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.6)
            if let failure = data.failure {
                Text(failure).font(.body).foregroundStyle(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 4) {
                    Text(data.headline).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(.white).contentTransition(.opacity)
                    if let detail = data.detail { InfoButton(id: "launch-info", title: data.headline, text: detail) }
                }
                .animation(.easeInOut(duration: 0.25), value: data.headline)
                steps
                chips
            }
            HStack(spacing: 12) {
                PillButton(id: "launch-cancel", title: data.failure != nil ? "Close" : (data.cleanCancel ? "Cancel" : "Stop game"), symbol: data.failure != nil ? "xmark" : "stop.fill",
                           style: data.failure != nil ? .glass : .danger, action: cancel)
                if let showSteam, data.failure == nil { PillButton(id: "launch-steam", title: "Show Steam window", symbol: "rectangle.on.rectangle", action: showSteam) }
            }
            .padding(.top, tight ? 2 : 6)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: vSize == .compact ? 5 : 9) {
            ForEach(data.steps) { step in
                HStack(spacing: 10) {
                    ZStack {
                        switch step.state {
                        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                        case .active: ProgressView().controlSize(.small).tint(Theme.accent)
                        case .pending: Image(systemName: "circle").foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .font(.system(size: 16)).frame(width: 20, height: 20)
                    Text(step.title).font(.system(size: 15, weight: step.state == .active ? .bold : .regular, design: .rounded))
                        .foregroundStyle(step.state == .pending ? .white.opacity(0.45) : .white)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: data.steps)
    }

    private var chips: some View {
        FlowLayout(spacing: 8) {
            ForEach(data.chips) { GlowChip(text: $0.text, symbol: $0.symbol, tint: .white).fixedSize() }
        }
    }

    /// The game inside a porthole: a round window with a glowing ring that fills as the launch moves on.
    private func porthole(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(.black.opacity(0.4))
            GameArtView(id: data.gameID, name: data.name, kind: .header).frame(width: size * 0.86, height: size * 0.86).clipShape(Circle())
            Circle().strokeBorder(.white.opacity(0.12), lineWidth: size * 0.05)
            Circle().trim(from: 0, to: max(0.02, data.progress)).rotation(.degrees(-90))
                .stroke(data.failure == nil ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.bad), style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                .shadow(color: (data.failure == nil ? Theme.accent : Theme.bad).opacity(0.8 * Theme.glowStrength), radius: 14)
                .animation(.easeInOut(duration: 0.6), value: data.progress)
            if data.failure == nil { Spinner(size: size) }
        }
        .frame(width: size, height: size)
    }

    private struct Spinner: View {
        let size: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
                let angle = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360
                Circle().trim(from: 0, to: 0.08).stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: size * 0.018, lineCap: .round))
                    .rotationEffect(.degrees(angle)).padding(size * 0.02)
            }
        }
    }
}
