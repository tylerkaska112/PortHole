// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

/// "Offline": shown by a screen that keeps a saved list, so the person knows why it does not refresh and that nothing is wrong.
struct OfflineChip: View {
    var detail = "showing your saved list"
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash").font(.system(size: 13, weight: .bold))
            Text("Offline").font(.system(size: 14, weight: .bold, design: .rounded))
            if !detail.isEmpty { Text("\u{00B7} \(detail)").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textDim) }
        }
        .foregroundStyle(Theme.warn)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.warn.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Offline, showing your saved list")
    }
}
