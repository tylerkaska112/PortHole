// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

/// GOG's own login page in a sheet; when signed in it shows the account and closes, like Epic's.
struct GogSignInView: View {
    @ObservedObject private var auth = GogAuth.shared
    @ObservedObject private var library = GogLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showPaste = false
    @State private var pasted = ""

    var body: some View {
        NavigationStack {
            Group {
                if let name = auth.accountName { account(name) } else { login }
            }
            .navigationTitle("GOG").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(auth.signedIn ? "Done" : "Cancel") { dismiss() } }
                if !auth.signedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Menu { Button("Paste a sign-in code or address") { showPaste = true } } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .alert("Sign-in code", isPresented: $showPaste) {
                TextField("code, or the whole address", text: $pasted).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Sign in") { auth.exchange(code: GogAuth.extractCode(from: pasted)); pasted = "" }
                Button("Cancel", role: .cancel) { pasted = "" }
            }
            .onAppear { auth.refresh() }
            .onChange(of: auth.accountName) { old, name in
                guard name != nil else { library.clear(); return }
                library.refresh()
                if old == nil { dismiss() }
            }
        }
    }

    private var login: some View {
        ZStack {
            GogLoginWebView { code in auth.exchange(code: code) }.ignoresSafeArea(edges: .bottom)
            if auth.isBusy {
                Color(uiColor: .systemBackground).opacity(0.85).ignoresSafeArea()
                ProgressView("Signing in\u{2026}")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let error = auth.signInError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
                    .padding(12).frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
    }

    private func account(_ name: String) -> some View {
        Form {
            Section {
                LabeledContent("Signed in as", value: name)
                LabeledContent("Games", value: library.isLoading ? "Loading\u{2026}" : "\(library.games.count)")
                Button("Sign out of GOG", role: .destructive) { auth.signOut(); library.clear() }
            }
            if let error = library.error {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
        }
    }
}
