// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI
import WebKit

/// itch.io sign-in with the person's own API key. The page where keys are made opens in the sheet (it is itch.io's own page, so the password stays
/// there); the key is pasted back and checked.
struct ItchSignInView: View {
    @ObservedObject private var auth = ItchAuth.shared
    @ObservedObject private var library = ItchLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var showPage = false

    var body: some View {
        NavigationStack {
            Group {
                if let name = auth.accountName { account(name) } else { login }
            }
            .navigationTitle("itch.io").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(auth.signedIn ? "Done" : "Cancel") { dismiss() } } }
            .onAppear { auth.refresh() }
            .onChange(of: auth.accountName) { old, name in
                guard name != nil else { library.clear(); return }
                library.refresh()
                if old == nil { dismiss() }
            }
            .sheet(isPresented: $showPage) { ItchKeyPage() }
        }
    }

    private var login: some View {
        Form {
            Section {
                Text("itch.io lets you make a personal API key. Porthole uses it only to list your games and download them; it stays in this device's Keychain.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { showPage = true } label: { Label("Open itch.io's API keys page", systemImage: "safari") }
                Text("Sign in there, tap Generate new API key, copy the key, and paste it below.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Your API key") {
                SecureField("Paste the key here", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button {
                    auth.signIn(apiKey: key)
                } label: {
                    if auth.isBusy { ProgressView() } else { Text("Sign in") }
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || auth.isBusy)
                if let error = auth.signInError { Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red) }
            }
        }
    }

    private func account(_ name: String) -> some View {
        Form {
            Section {
                LabeledContent("Signed in as", value: name)
                LabeledContent("Games", value: library.isLoading ? "Loading\u{2026}" : "\(library.games.count)")
                Button("Sign out of itch.io", role: .destructive) { auth.signOut(); library.clear() }
            }
            if let error = library.error {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
        }
    }
}

/// itch.io's API keys page in a web view (own cookies for the sheet; closing it forgets the sign-in there).
private struct ItchKeyPage: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ItchWebView(url: URL(string: "https://itch.io/user/settings/api-keys")!)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("API keys").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct ItchWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.load(URLRequest(url: url))
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
