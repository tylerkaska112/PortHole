// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
// Epic Games in Porthole's own screens (the sign-in, library and downloads underneath are Madeira pull request 207's, in Sources/Epic).
import SwiftUI

/// The Epic account and the way into its games, as a group of Settings > Stores and JIT.
struct EpicSettingsGroup: View {
    @ObservedObject private var auth = EpicAuth.shared
    @ObservedObject private var library = EpicLibrary.shared
    @State private var signIn = false
    @State private var confirmSignOut = false

    var body: some View {
        SettingsGroup(title: "Epic Games") {
            if let name = auth.accountName {
                ValueRow(id: "ep-account", symbol: "person.fill", title: "Signed in as", value: name.isEmpty ? "Epic account" : name)
                // The library itself is in the Stores tab: this is only a count, so it is not a button.
                ValueRow(id: "ep-library", symbol: "books.vertical.fill", title: "Your Epic games",
                         value: library.isLoading ? "Loading\u{2026}" : "\(library.games.count) with a Windows version")
                ActionRow(id: "ep-out", symbol: "rectangle.portrait.and.arrow.right", title: "Sign out of Epic Games", destructive: true, chevron: false) { confirmSignOut = true }
            } else {
                ActionRow(id: "ep-in", symbol: "person.badge.key.fill", title: "Sign in to Epic Games",
                          info: "You sign in on Epic's own page. The sign-in token stays in this device's Keychain; Porthole never sees your password, and signing out removes the token.") { signIn = true }
            }
        }
        .sheet(isPresented: $signIn) { EpicSignInView() }
        .confirm("Sign out of Epic Games?", message: "Games you installed stay on this device.", confirmTitle: "Sign out", destructive: true, isPresented: $confirmSignOut) {
            auth.signOut(); library.clear()
        }
        .task { if auth.signedIn { library.refreshIfStale() } }
    }
}
