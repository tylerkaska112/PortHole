// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI
import LauncherCore

/// One version from Settings > Updates > Versions: what it added, changed and fixed, and at the bottom the button that installs it.
struct ReleaseNotesSheet: View {
    let release: Release
    let isInstalled: Bool
    let isOlder: Bool
    /// A certificate and profile are set up, so the app can sign and install it itself; otherwise the button downloads the file.
    let canSign: Bool
    let busy: Bool
    let scope: FocusScope
    let install: () -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            AmbientBackdrop(animated: false)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(release.title).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                        Text(subtitle).font(.footnote).foregroundStyle(Theme.textDim).lineLimit(1)
                    }
                    Spacer()
                    PillButton(id: "rn-close", title: "Close", symbol: "xmark", action: close)
                }
                .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 8)
                FocusScroll {
                    VStack(alignment: .leading, spacing: 16) {
                        if isInstalled || isOlder { statusChip }
                        if !release.summary.isEmpty {
                            Text(release.summary).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 6)
                        }
                        section("New", symbol: "sparkles", tint: Theme.accent, items: release.added)
                        section("Changed", symbol: "arrow.triangle.2.circlepath", tint: .teal, items: release.changed)
                        section("Fixed", symbol: "wrench.and.screwdriver.fill", tint: Theme.good, items: release.fixed)
                        if !release.hasNotes {
                            Text("No notes were published for this version.").font(.subheadline).foregroundStyle(Theme.textDim).padding(.horizontal, 6)
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
                bottomBar
            }
        }
        .navScope(scope)
        .onAppear { scope.onBack = close; scope.defaultFocus = "rn-install"; scope.focused = "rn-install" }
        .presentationBackground(Theme.background)
        .preferredColorScheme(Theme.scheme)
    }

    // MARK: Pieces

    private var subtitle: String {
        var parts: [String] = []
        if let date = release.publishedAt { parts.append(date.formatted(date: .long, time: .omitted)) }
        if let size = release.size, size > 0 { parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
        if let os = release.minimumOS, !os.isEmpty { parts.append("iOS \(os) or later") }
        return parts.isEmpty ? "A published version" : parts.joined(separator: " \u{00B7} ")
    }

    private var statusChip: some View {
        let installed = isInstalled
        return Label(installed ? "This is the version you have" : "Older than the version you have", systemImage: installed ? "checkmark.circle.fill" : "clock.arrow.circlepath")
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(installed ? Theme.good : Theme.warn)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background((installed ? Theme.good : Theme.warn).opacity(0.15), in: Capsule())
            .padding(.horizontal, 6)
    }

    @ViewBuilder private func section(_ title: String, symbol: String, tint: Color, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(tint)
                ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(tint).frame(width: 6, height: 6).offset(y: -2)
                        Text(line).font(.system(size: 15)).foregroundStyle(Theme.text.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            .focusTarget("rn-\(title)", radius: 16, scale: 1.01, action: {})
        }
    }

    private var installTitle: String {
        if !canSign { return "Download \(release.version)" }
        if isInstalled { return "Install \(release.version) again" }
        if isOlder { return "Go back to \(release.version)" }
        return "Install \(release.version)"
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if canSign, isOlder, !isInstalled {
                Text("This is older than the version you have. Your games and settings are kept, but an older version may not understand data a newer one saved.")
                    .font(.footnote).foregroundStyle(Theme.warn).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if busy { Text("An update is already running.").font(.footnote).foregroundStyle(Theme.textDim) }
            PillButton(id: "rn-install", title: installTitle, symbol: canSign ? "arrow.down.circle.fill" : "square.and.arrow.down", style: .primary, enabled: !busy, action: install)
        }
        .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(Theme.panel.opacity(0.95))
    }
}


/// Everything that is new between the version the person has and the newest one, in one place: the New, Changed and Fixed lists of every version since, each line
/// tagged with its version, and the install button at the bottom. For someone who has not updated in a while.
struct SinceYourVersionSheet: View {
    /// The installed version, "0.50.262 (358)".
    let installed: String
    /// Every release newer than the installed one, newest first.
    let releases: [Release]
    let canSign: Bool
    let busy: Bool
    let scope: FocusScope
    let install: () -> Void
    let close: () -> Void

    private var latest: Release? { releases.first }
    private func lines(_ keyPath: KeyPath<Release, [String]>) -> [(version: String, text: String)] {
        releases.flatMap { r in r[keyPath: keyPath].map { (r.version, $0) } }
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(animated: false)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Since your version").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(installed) \u{2192} \(latest?.title ?? "?") \u{00B7} \(releases.count) version\(releases.count == 1 ? "" : "s")")
                            .font(.footnote).foregroundStyle(Theme.textDim).lineLimit(1)
                    }
                    Spacer()
                    PillButton(id: "sy-close", title: "Close", symbol: "xmark", action: close)
                }
                .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 8)
                FocusScroll {
                    VStack(alignment: .leading, spacing: 16) {
                        section("New", symbol: "sparkles", tint: Theme.accent, items: lines(\.added))
                        section("Changed", symbol: "arrow.triangle.2.circlepath", tint: .teal, items: lines(\.changed))
                        section("Fixed", symbol: "wrench.and.screwdriver.fill", tint: Theme.good, items: lines(\.fixed))
                        if lines(\.added).isEmpty && lines(\.changed).isEmpty && lines(\.fixed).isEmpty {
                            Text("These versions were published without notes. Their one-line summaries are below.").font(.subheadline).foregroundStyle(Theme.textDim).padding(.horizontal, 6)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Version by version", systemImage: "list.bullet").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Theme.textDim)
                            ForEach(releases) { r in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                                    if !r.summary.isEmpty { Text(r.summary).font(.footnote).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true) }
                                }
                            }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                        .focusTarget("sy-versions", radius: 16, scale: 1.01, action: {})
                    }
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
                VStack(spacing: 8) {
                    if busy { Text("An update is already running.").font(.footnote).foregroundStyle(Theme.textDim) }
                    PillButton(id: "sy-install", title: canSign ? "Update to \(latest?.version ?? "")" : "Download \(latest?.version ?? "")",
                               symbol: canSign ? "arrow.down.circle.fill" : "square.and.arrow.down", style: .primary, enabled: !busy && latest != nil, action: install)
                }
                .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 14)
                .frame(maxWidth: .infinity)
                .background(Theme.panel.opacity(0.95))
            }
        }
        .navScope(scope)
        .onAppear { scope.onBack = close; scope.defaultFocus = "sy-install"; scope.focused = "sy-install" }
        .presentationBackground(Theme.background)
        .preferredColorScheme(Theme.scheme)
    }

    @ViewBuilder private func section(_ title: String, symbol: String, tint: Color, items: [(version: String, text: String)]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("\(title) \u{00B7} \(items.count)", systemImage: symbol).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(tint)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(tint).frame(width: 6, height: 6).offset(y: -2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.text).font(.system(size: 15)).foregroundStyle(Theme.text.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
                            Text(item.version).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(tint)
                                .padding(.horizontal, 7).padding(.vertical, 2).background(tint.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            .focusTarget("sy-\(title)", radius: 16, scale: 1.01, action: {})
        }
    }
}
