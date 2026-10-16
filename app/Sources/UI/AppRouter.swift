// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI
import Observation

/// The app's top-level sections. On iPhone they are the tab bar; on iPad the same list becomes a sidebar.
enum AppTab: Hashable { case library, stores, compatibility, settings }

/// What the Stores tab shows: its list of launchers (nil), every launcher's games on one page, or one launcher's library.
enum StoresSelection: Hashable { case all, store(GameStore), downloads }

/// Where the person is, and what is open on top of it, so any screen can send them somewhere else (a banner that says "update ready" opens Settings, and so on).
@Observable
@MainActor
final class AppRouter {
    var tab: AppTab = .library
    var showAdd = false
    var showSetup = false
    var showUpdates = false
    var pickInstaller = false
    /// The games opened on the Home section (a game's page sits on top of the home screen).
    var homePath = NavigationPath()
    /// Which Settings page to open next time the Settings section appears (nil = the list).
    var settingsPage: SettingsPage?
    /// The Settings page being shown. Kept here, not in the screen, because changing the theme rebuilds the screen and it must come back to the same page.
    var settingsSelection: SettingsPage?

    /// The Stores tab's page (nil = the list of launchers).
    var storesSelection: StoresSelection?

    /// Where the shared Downloads page was opened from, so Back returns there.
    var downloadsReturn: StoresSelection?

    func openSteam() { openStore(.steam) }
    func openDownloads() {
        if storesSelection != .downloads { downloadsReturn = storesSelection }
        storesSelection = .downloads; tab = .stores
    }
    func closeDownloads() { storesSelection = downloadsReturn; downloadsReturn = nil }
    func openStore(_ store: GameStore) { storesSelection = .store(store); tab = .stores }
    func openStores() { storesSelection = nil; tab = .stores }
    func openSettings(_ page: SettingsPage? = nil) { settingsPage = page; tab = .settings }
}

/// The pages inside Settings.
enum SettingsPage: String, Hashable, CaseIterable, Identifiable {
    case play, accounts, saves, storage, updates, app, advanced, report
    var id: String { rawValue }
}
