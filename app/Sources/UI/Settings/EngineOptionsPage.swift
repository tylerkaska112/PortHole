// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

/// Settings > Engine options: the switches of the game engine (Madeira) that Porthole has no other screen for. Every row starts on "Default", which
/// leaves the engine exactly as it was; a row only writes madeira.cfg when you change it, and "Default" removes only that key.
struct EngineOptionsPage: View {
    @State private var values: [String: String] = [:]
    @State private var rumbleMessage: String?

    var body: some View {
        PageScaffold(title: "Engine options", symbol: "slider.horizontal.2.square") {
            Text("Switches of the game engine. Every row starts on Default, which leaves the engine as it is. Most apply the next time a game starts. Settings you already have, such as swap, video memory and resolution, are on their own pages and are not changed here.")
                .font(.footnote).foregroundStyle(Theme.textDim).padding(.horizontal, 6)
            ForEach(EngineOptions.groups) { group in
                SettingsGroup(title: group.title) {
                    ForEach(group.options) { option in
                        ChoiceRow(id: "eo-\(option.key)", symbol: option.symbol, title: option.title, info: option.info,
                                  options: EngineOptions.choices(for: option, current: values[option.key] ?? ""),
                                  selection: Binding(get: { values[option.key] ?? "" },
                                                     set: { values[option.key] = $0; EngineOptions.set(option.key, $0); EngineOptionsChanged.post(option.key) }))
                    }
                }
            }
            SettingsGroup(title: "Try it") {
                ActionRow(id: "eo-rumble-test", symbol: "waveform", title: "Test controller rumble", subtitle: rumbleMessage ?? "Buzzes the left, then the right motor of the first controller", chevron: false) {
                    rumbleMessage = "Testing\u{2026}"
                    PadRumble.shared.test { rumbleMessage = $0 }
                }
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        var v: [String: String] = [:]
        for group in EngineOptions.groups { for option in group.options { v[option.key] = EngineOptions.value(option.key) } }
        values = v
    }
}

/// Lets live pieces (the screen-rate hold, the controller bridge) react to a change without waiting for the next start.
enum EngineOptionsChanged {
    static let name = Notification.Name("porthole.engineOptionChanged")
    static func post(_ key: String) { NotificationCenter.default.post(name: name, object: key) }
}
