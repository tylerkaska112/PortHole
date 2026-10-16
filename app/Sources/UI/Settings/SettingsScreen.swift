// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

/// Settings: a grouped list of pages on the left and the chosen page on the right (one at a time on a narrow screen). Everything is reachable with the D-pad.
struct SettingsScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(UpdateService.self) private var updates
    @Environment(\.focusScope) private var scope
    private var selection: SettingsPage? {
        get { router.settingsSelection }
        nonmutating set { router.settingsSelection = newValue }
    }
    @AppStorage("f4.setupDone") private var setupDone = false
    @ObservedObject private var problems = ProblemTracker.shared

    static let pages: [SettingsPage] = [.play, .accounts, .saves, .storage, .updates, .app, .advanced, .report]

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 700
            Group {
                if wide {
                    HStack(spacing: 0) {
                        sidebar(wide: true).frame(width: 300)
                        Rectangle().fill(Theme.line).frame(width: 1)
                        detail(wide: true)
                    }
                } else if let page = selection {
                    VStack(alignment: .leading, spacing: 0) {
                        PillButton(id: "settings-back", title: "Settings", symbol: "chevron.left") { selection = nil }.padding(.horizontal, 20).padding(.top, 8)
                        detail(wide: false, page: page)
                    }
                } else {
                    sidebar(wide: false)
                }
            }
            .onAppear {
                if let page = router.settingsPage { selection = page; router.settingsPage = nil }
                else if wide && selection == nil { selection = .play }
            }
            .onChange(of: router.settingsPage) { _, page in if let page { selection = page; router.settingsPage = nil } }
            .onNavBack {
                if wide {
                    if let focused = scope?.focused as? String, focused.hasPrefix("set-") { return false }
                    scope?.focused = "set-\((selection ?? .play).rawValue)"; return true
                }
                if selection != nil { selection = nil; return true }
                return false
            }
        }
    }

    // MARK: Pieces

    private func sidebar(wide: Bool) -> some View {
        FocusScroll {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text).padding(.horizontal, 6)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Self.pages) { page in
                        SidebarRow(id: "set-\(page.rawValue)", symbol: page.symbol, tint: page.tint, title: page.title, detail: badge(for: page),
                                   selected: wide && selection == page,
                                   onFocus: wide ? { selection = page } : nil) {
                            if wide { scope?.handle(.move(.right)) } else { selection = page }
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 16)
            .frame(maxWidth: wide ? .infinity : 640, alignment: .leading).frame(maxWidth: .infinity, alignment: wide ? .leading : .center)
        }
    }

    private func detail(wide: Bool, page: SettingsPage? = nil) -> some View {
        let shown = page ?? selection
        return FocusScroll {
            Group {
                if let shown { SettingsPageView(page: shown).id(shown) }
                else { Text("Choose a page").foregroundStyle(Theme.textDim).frame(maxWidth: .infinity).padding(.top, 80) }
            }
            .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private func badge(for page: SettingsPage) -> String? {
        switch page {
        case .updates: return updates.available != nil ? "1" : nil
        case .app: return setupDone ? nil : "!"
        case .accounts: return BuiltinJIT.hasPairing ? nil : "!"
        case .report: return problems.unseen > 0 ? "\(problems.unseen)" : (CrashEvidence.latestUnreported() != nil ? "!" : nil)
        default: return nil
        }
    }
}

extension SettingsPage {
    var title: String {
        switch self {
        case .play: "Play"
        case .accounts: "Stores and JIT"
        case .saves: "Saves"
        case .storage: "Storage"
        case .updates: "Updates"
        case .app: "App"
        case .advanced: "Advanced"
        case .report: "Report a problem"
        }
    }
    var symbol: String {
        switch self {
        case .play: "gamecontroller.fill"
        case .accounts: "bolt.horizontal.fill"
        case .saves: "externaldrive.badge.icloud"
        case .storage: "internaldrive.fill"
        case .updates: "arrow.triangle.2.circlepath"
        case .app: "paintpalette.fill"
        case .advanced: "wrench.and.screwdriver.fill"
        case .report: "exclamationmark.bubble.fill"
        }
    }
    var tint: Color {
        switch self {
        case .play: .blue
        case .accounts: .green
        case .saves: .teal
        case .storage: .orange
        case .updates: .mint
        case .app: .pink
        case .advanced: .gray
        case .report: .red
        }
    }
}

/// A page's content. Most pages are several of the older, smaller ones one after another.
struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .play:
            CombinedPage(title: "Play", symbol: "gamecontroller.fill") { DisplayPage(); PerformancePage(); SoundPage(); ControlsPage() }
        case .accounts:
            CombinedPage(title: "Stores and JIT", symbol: "bolt.horizontal.fill") { SteamSettingsPage(); ConnectionPage() }
        case .saves: SavesPage()
        case .storage: StoragePage()
        case .updates: UpdatesPage()
        case .app:
            CombinedPage(title: "App", symbol: "paintpalette.fill") { AppearancePage(); ReportsSettingsPage(); SetupPage(); GuidesPage(); AboutPage() }
        case .advanced:
            CombinedPage(title: "Advanced", symbol: "wrench.and.screwdriver.fill") { AdvancedPage(); EngineOptionsPage(); LogPage() }
        case .report: ReportProblemPage()
        }
    }
}
