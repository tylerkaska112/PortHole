// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

// MARK: - Badge

extension CompatPast {
    var color: Color { verdict.color }
}

extension CompatVerdict {
    var color: Color {
        switch self { case .great: Theme.good; case .playable: Theme.warn; case .broken: Theme.bad }
    }
}

/// The compatibility badge: a coloured pill with an icon and a short verdict, like the Steam Deck badge but for this app.
/// The compatibility badge on a library tile: how it runs here when reports say, what it used to do on an older engine, or that it has not been tested. Nothing when unknown.
struct CompatTileBadge: View {
    let badge: CompatBadge?
    let untested: Bool
    var body: some View {
        if let verdict = badge?.verdict { CompatBadgePill(verdict: verdict, compact: true) }
        else if let past = badge?.past { CompatPastPill(past: past, compact: true) }
        else if untested || badge?.needsReview == true { CompatUntestedPill(compact: true) }
    }
}

struct CompatBadgePill: View {
    let verdict: CompatVerdict
    var compact = false
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: verdict.symbol).font(.system(size: compact ? 10 : 13, weight: .bold))
            Text(compact ? verdict.short.uppercased() : verdict.title).font(.system(size: compact ? 10 : 14, weight: compact ? .heavy : .semibold)).tracking(compact ? 0.6 : 0).lineLimit(1).fixedSize()
        }
        .foregroundStyle(compact ? Color.white : verdict.color)
        .padding(.horizontal, compact ? 8 : 12).padding(.vertical, compact ? 4 : 7)
        .background(compact ? AnyShapeStyle(verdict.color.opacity(0.92)) : AnyShapeStyle(verdict.color.opacity(0.15)), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Compatibility: \(verdict.title)")
    }
}

/// "Not yet tested": nobody has reported this game on this version of the game engine, so nothing is known about how it runs. Grey on purpose: it is not a verdict.
struct CompatUntestedPill: View {
    var compact = false
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "questionmark.circle.fill").font(.system(size: compact ? 10 : 13, weight: .bold))
            Text(compact ? "NOT YET TESTED" : "Not yet tested").font(.system(size: compact ? 10 : 14, weight: compact ? .heavy : .semibold)).tracking(compact ? 0.6 : 0).lineLimit(1).fixedSize()
        }
        .foregroundStyle(compact ? Color.white : Theme.textDim)
        .padding(.horizontal, compact ? 8 : 12).padding(.vertical, compact ? 4 : 7)
        .background(compact ? AnyShapeStyle(Color.gray.opacity(0.85)) : AnyShapeStyle(Color.gray.opacity(0.18)), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Compatibility: not yet tested")
    }
}

/// "Worked in v0.50.34", "Somewhat worked in v0.50.34" or "Didn't work in v0.50.34": how it ran on an earlier engine. Outlined, not filled, to show it is a past result and not a verdict.
struct CompatPastPill: View {
    let past: CompatPast
    var compact = false
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: past.symbol).font(.system(size: compact ? 10 : 13, weight: .bold))
            Text(compact ? past.text.uppercased() : past.text).font(.system(size: compact ? 10 : 14, weight: compact ? .heavy : .semibold)).tracking(compact ? 0.4 : 0).lineLimit(1).fixedSize()
        }
        .foregroundStyle(past.color)
        .padding(.horizontal, compact ? 8 : 12).padding(.vertical, compact ? 4 : 7)
        .background(past.color.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(past.color.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Compatibility on an earlier version: \(past.text)")
    }
}
