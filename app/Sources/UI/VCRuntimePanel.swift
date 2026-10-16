// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

/// The Visual C++ runtime download (Microsoft's own installer, checked and unpacked on the device), as kit rows. Used in the setup guide.
struct VCRuntimePanel: View {
    @State private var installer = VCRuntimeInstaller.shared

    var body: some View {
        SettingsGroup {
            ValueRow(id: "vc-state", symbol: installer.available ? "checkmark.seal.fill" : "shippingbox.fill", title: "Visual C++ runtime", value: installer.available ? (installer.installed ? "Installed" : "Included") : "Not downloaded",
                     statusColor: installer.available ? Theme.good : Theme.warn)
            switch installer.state {
            case .downloading(let fraction):
                HStack(spacing: 10) { ProgressView(value: fraction).tint(Theme.accent); Text("\(Int(fraction * 100))%").font(.footnote.monospacedDigit()).foregroundStyle(Theme.textDim) }.padding(.horizontal, 6)
            case .unpacking:
                HStack(spacing: 8) { ProgressView().tint(Theme.accent); Text("Checking and unpacking\u{2026}").font(.footnote).foregroundStyle(Theme.textDim) }.padding(.horizontal, 6)
            case .failed(let message):
                Text(message).font(.footnote).foregroundStyle(Theme.warn).padding(.horizontal, 6)
            case .idle: EmptyView()
            }
            if !installer.available && !installer.busy {
                ActionRow(id: "vc-main", symbol: "arrow.down.circle.fill", title: "Download", subtitle: "About 25 MB, from Microsoft", chevron: false, prominent: true) { Task { await installer.install() } }
            } else if installer.state == .idle, installer.installed {
                ActionRow(id: "vc-remove", symbol: "trash.fill", title: "Remove the downloaded copy", destructive: true, chevron: false) { installer.remove() }
            } else {
                ValueRow(id: "vc-main", symbol: "hourglass", title: installer.busy ? "Working\u{2026}" : "Ready", value: "")
            }
        }
    }
}
