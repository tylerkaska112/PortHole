// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

/// Search Steam by hand when the automatic match is wrong (or missing).
struct SteamPickerView: View {
    let initialTerm: String
    var onPick: (SteamArt.Match?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scope = FocusScope()
    @State private var term = ""
    @State private var results: [SteamArt.Match] = []
    @State private var searching = false

    var body: some View {
        KitSheet(title: "Steam artwork", scope: scope, defaultFocus: results.first.map { "sp-\($0.id)" } ?? "sp-search", close: { dismiss() }) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsGroup {
                    TextFieldRow(id: "sp-search", symbol: "magnifyingglass", title: "Game name", placeholder: "Search Steam", text: $term)
                    PillButton(id: "sp-go", title: searching ? "Searching\u{2026}" : "Search", symbol: "magnifyingglass", style: .primary, enabled: !searching) { Task { await run() } }
                }
                if !results.isEmpty {
                    SettingsGroup(title: "Pick the match") {
                        ForEach(results) { match in
                            RowBase(id: "sp-\(match.id)", title: match.name, action: { onPick(match); dismiss() }) {
                                AsyncImage(url: match.thumb) { $0.resizable().scaledToFill() } placeholder: { Theme.panelHigh }
                                    .frame(width: 92, height: 35).clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                } else if !searching {
                    Text("No results.").foregroundStyle(Theme.textDim).padding(.horizontal, 6)
                }
                ActionRow(id: "sp-none", symbol: "photo.badge.minus", title: "No artwork", chevron: false) { onPick(nil); dismiss() }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
        }
        .task { term = initialTerm; await run() }
    }

    private func run() async {
        searching = true; results = await SteamArt.shared.search(term); searching = false
        scope.defaultFocus = results.first.map { "sp-\($0.id)" } ?? "sp-search"
        if let first = results.first { scope.focused = "sp-\(first.id)" }
    }
}
