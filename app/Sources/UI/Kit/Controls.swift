// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

// The pieces the new screens are built from. Each one is a focus target, so the D-pad / arrow keys can reach it, and each shows the glow when selected.

/// Lays children out in equal columns that are at least `minWidth` wide, all built eagerly so the D-pad can reach every one (a lazy grid only knows the rows on screen).
struct AdaptiveGrid: SwiftUI.Layout {
    var minWidth: CGFloat = 220
    var spacing: CGFloat = 18

    private func columns(for width: CGFloat) -> Int { max(1, Int((width + spacing) / (minWidth + spacing))) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let cols = columns(for: width), itemW = (width - CGFloat(cols - 1) * spacing) / CGFloat(cols)
        var y: CGFloat = 0
        for rowStart in stride(from: 0, to: subviews.count, by: cols) {
            let h = subviews[rowStart..<min(rowStart + cols, subviews.count)].map { $0.sizeThatFits(.init(width: itemW, height: nil)).height }.max() ?? 0
            y += h + spacing
        }
        return CGSize(width: width, height: max(0, y - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        let cols = columns(for: bounds.width), itemW = (bounds.width - CGFloat(cols - 1) * spacing) / CGFloat(cols)
        var y = bounds.minY
        for rowStart in stride(from: 0, to: subviews.count, by: cols) {
            let row = subviews[rowStart..<min(rowStart + cols, subviews.count)]
            let h = row.map { $0.sizeThatFits(.init(width: itemW, height: nil)).height }.max() ?? 0
            for (i, v) in row.enumerated() { v.place(at: CGPoint(x: bounds.minX + CGFloat(i) * (itemW + spacing), y: y), proposal: .init(width: itemW, height: h)) }
            y += h + spacing
        }
    }
}

/// A capsule button. `.primary` is the glowing accent one; `.glass` is a quiet one.
struct PillButton: View {
    enum Style { case primary, glass, danger }
    let id: AnyHashable
    let title: String
    var symbol: String?
    var style: Style = .glass
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: { if enabled { action() } }) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.subheadline.weight(.bold)) }
                Text(title).font(.system(size: 16, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(foreground)
            .padding(.vertical, 12).padding(.horizontal, 22)
            .frame(minHeight: 44)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(style == .glass ? Theme.line : .clear, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .focusTarget(id, radius: 30, scale: 1.05, action: { if enabled { action() } })
    }

    private var foreground: Color { switch style { case .primary: Theme.onAccent; case .glass: Theme.text; case .danger: Theme.bad } }
    private var background: AnyShapeStyle {
        switch style {
        case .primary: AnyShapeStyle(Theme.accentGradient)
        case .glass: AnyShapeStyle(Theme.panelHigh)
        case .danger: AnyShapeStyle(Theme.bad.opacity(0.14))
        }
    }
}

/// The small "i" that opens a short explanation in a pop-up, so screens do not need paragraphs of text.
/// A small bottom sheet (it can't be cut off by the screen's edge the way an arrow pop-up can, on a phone or an iPad).
struct InfoButton: View {
    let id: AnyHashable
    var title: String?
    let text: String
    @State private var shown = false
    @State private var popoverScope = FocusScope()

    var body: some View {
        Button { shown = true } label: {
            Image(systemName: "info.circle").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.textDim)
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusTarget(id, radius: 22, scale: 1.12) { shown = true }
        .accessibilityLabel("More information")
        .sheet(isPresented: $shown) {
            InfoPopover(title: title, text: text, scope: popoverScope) { shown = false }
        }
    }
}

struct InfoPopover: View {
    let title: String?
    let text: String
    let scope: FocusScope
    let dismiss: () -> Void

    /// About as tall as the text needs, so short notes stay small.
    private var height: CGFloat {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / 34))) }
        return min(max(CGFloat(lines) * 22 + (title == nil ? 130 : 170), 220), 620)
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(animated: false)
            VStack(alignment: .leading, spacing: 14) {
                if let title { Text(title).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text) }
                ScrollView { Text(text).font(.system(size: 16)).foregroundStyle(Theme.text.opacity(0.92)).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true) }
                HStack { Spacer(); PillButton(id: "info-ok", title: "Got it", style: .primary, action: dismiss) }
            }
            .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 16)
        }
        .navScope(scope)
        .onAppear { scope.onBack = dismiss; scope.defaultFocus = "info-ok"; scope.focused = "info-ok" }
        .presentationDetents([.height(height), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .preferredColorScheme(Theme.scheme)
    }
}

/// A short label with a symbol: "Steam", "64-bit", "Balanced".
struct GlowChip: View {
    let text: String
    var symbol: String?
    var tint: Color = Theme.textDim
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.semibold)).lineLimit(1).fixedSize()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 1))
    }
}

/// The hints for a controller or keyboard at the bottom of a screen.
struct ControllerHints: View {
    /// nil = the standard guide, named for the connected controller (✕ Select, ○ Back, L1 R1 Switch on a PlayStation pad).
    var items: [(String, String)]?
    private var kind: ControllerKind { ControllerInput.shared.kind }
    private var shown: [(String, String)] {
        items ?? [(kind.glyph("A"), "Select"), (kind.glyph("B"), "Back"), ("\(kind.glyph("LB")) \(kind.glyph("RB"))", "Switch")]
    }
    var body: some View {
        HStack(spacing: 16) {
            if items == nil, kind != .none {
                HStack(spacing: 5) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 12, weight: .semibold))
                    Text(kind.displayName).font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.textDim)
            }
            ForEach(shown, id: \.0) { glyph, label in
                HStack(spacing: 6) {
                    Text(glyph).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 22).background(Theme.accent, in: Capsule())
                    Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.textDim)
                }
            }
        }
    }
}

/// A heading above a group of tiles or rows.
struct SectionTitle: View {
    let text: String
    var trailing: AnyView?
    init(_ text: String, trailing: AnyView? = nil) { self.text = text; self.trailing = trailing }
    var body: some View {
        HStack {
            Text(text).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
            Spacer()
            trailing
        }
    }
}

/// Lays children out in a row and wraps to the next line when they run out of width (for chips).
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}


/// Two or three choices in one capsule; the chosen one is filled with the accent.
struct SegmentedPills: View {
    struct Option: Identifiable { let id: String; let title: String }
    let options: [Option]
    let selection: String
    let pick: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let on = selection == option.id
                Button { pick(option.id) } label: {
                    Text(option.title).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1).fixedSize()
                        .foregroundStyle(on ? Theme.onAccent : Theme.textDim)
                        .padding(.horizontal, 18).frame(minHeight: 40)
                        .background { if on { Capsule().fill(Theme.accentGradient) } }
                }
                .buttonStyle(.plain)
                .focusTarget("seg-\(option.id)", radius: 20, scale: 1.06) { pick(option.id) }
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// A round button with only a symbol, for the things that are obvious from the picture (refresh, select).
struct IconPillButton: View {
    let id: AnyHashable
    let symbol: String
    let label: String
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .bold))
                .foregroundStyle(on ? Theme.onAccent : Theme.text)
                .frame(width: 44, height: 44)
                .background { if on { Circle().fill(Theme.accentGradient) } else { Circle().fill(Theme.panelHigh) } }
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: on ? 0 : 1))
        }
        .buttonStyle(.plain)
        .focusTarget(id, radius: 22, scale: 1.08, action: action)
        .accessibilityLabel(label)
    }
}
