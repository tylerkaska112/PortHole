// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

struct ShellTab: Identifiable, Equatable {
    let id: String
    var title: String
    var symbol: String
}

/// The brand mark: the porthole from the app icon, with the sea inside (a transparent picture, drawn by tools/make_icon.swift).
struct PortholeMark: View {
    var size: CGFloat = 34
    /// From the asset catalog; the simulator preview has the same picture as a plain file in its bundle.
    private static let picture: UIImage? = UIImage(named: "PortholeMark")
        ?? Bundle.main.path(forResource: "PortholeMark", ofType: "png").flatMap { UIImage(contentsOfFile: $0) }

    var body: some View {
        Group {
            if let picture = Self.picture { Image(uiImage: picture).resizable().interpolation(.high).scaledToFit() } else { Color.clear }
        }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.35), radius: size * 0.08, y: size * 0.05)
            .accessibilityHidden(true)
    }
}

/// The frame of the app: one slim bar along the top (the brand mark, the sections as plain words that scroll sideways when they do not fit, and the clock),
/// and the current section's content under it. The same bar on a phone and an iPad.
struct AppShell<Content: View>: View {
    let tabs: [ShellTab]
    @Binding var selection: String
    var showHints = false
    /// The question mark in the bar: explains the screen that is open. Nil hides it.
    var onHelp: (() -> Void)?
    @ViewBuilder var content: Content
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    private var roomy: Bool { hSize == .regular }

    var body: some View {
        ZStack {
            AmbientBackdrop()
            VStack(spacing: 0) {
                topBar
                content
                if showHints { ControllerHints().padding(.vertical, 8) }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: roomy ? 22 : 12) {
            HStack(spacing: 10) {
                PortholeMark(size: vSize == .compact ? 30 : 38)
                if roomy || vSize == .compact { Text("Porthole").font(.system(size: 21, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text).lineLimit(1).fixedSize() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Porthole")
            tabStrip
            HStack(spacing: roomy ? 14 : 8) {
                if let onHelp { HelpChip(action: onHelp) }
                if roomy || vSize == .compact { Clock() }   // upright on a phone the system bar already shows the time
            }
            .fixedSize()
        }
        .padding(.horizontal, roomy ? 32 : 16).padding(.top, vSize == .compact ? 4 : 10).padding(.bottom, vSize == .compact ? 2 : 6)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The sections. A controller's shoulder buttons step through them, so the bar says so.
    private var tabStrip: some View {
        HStack(spacing: 8) {
            if showHints { ShoulderGlyph(text: ControllerInput.shared.kind.glyph("LB")) }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: roomy ? 10 : 2) {
                        ForEach(tabs) { tab in TabPill(tab: tab, selected: selection == tab.id, roomy: roomy) { selection = tab.id }.id(tab.id) }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 6)
                }
                .onChange(of: selection) { _, id in withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) } }
            }
            if showHints { ShoulderGlyph(text: ControllerInput.shared.kind.glyph("RB")) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The question mark in the bar.
private struct HelpChip: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle").font(.system(size: 21, weight: .semibold)).foregroundStyle(Theme.textDim)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusTarget("shell-help", radius: 22, scale: 1.08, action: action)
        .accessibilityLabel("Help for this screen")
    }
}

private struct ShoulderGlyph: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.textDim)
            .padding(.horizontal, 6).padding(.vertical, 3).background(Theme.panel, in: Capsule())
    }
}

/// The time, on the right of the bar.
private struct Clock: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour().minute()).font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.text)
        }
    }
}

/// A section name in the bar: plain words, the chosen one bright with a line under it.
struct TabPill: View {
    let tab: ShellTab
    let selected: Bool
    var roomy = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tab.title)
                .font(.system(size: roomy ? 19 : 15, weight: selected ? .heavy : .semibold, design: .rounded))
                .foregroundStyle(selected ? Theme.text : Theme.textDim)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, roomy ? 16 : 9).padding(.vertical, 8)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.2), value: selected)
        }
        .buttonStyle(.plain)
        // Not a D-pad target on purpose: the sections change with LB and RB (RootView) or a tap, so Up never lands on the bar and Left / Right never wander along it.
        .accessibilityLabel(tab.title)
    }
}
