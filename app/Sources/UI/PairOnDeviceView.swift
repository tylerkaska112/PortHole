// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

/// Walks the person through getting a pairing file from this iPhone itself (iOS 27 and later).
struct PairOnDeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pairing = OnDevicePairing.shared

    @State private var scope = FocusScope()

    var body: some View {
        KitSheet(title: "Pair this device", closeTitle: "Done", closeSymbol: "checkmark", scope: scope, defaultFocus: "pair-main", close: { if pairing.isRunning { pairing.cancel() }; dismiss() }) {
            VStack(alignment: .leading, spacing: 16) {
                if !OnDevicePairing.isSupported { unsupported }
                else {
                    steps
                    status
                    if let note = pairing.note { Text("That try didn't work: \(note)").font(.footnote).foregroundStyle(Theme.warn).padding(.horizontal, 6) }
                    controls
                    if !pairing.trace.isEmpty { details }
                    HStack(spacing: 2) {
                        Text("Needs iOS 27+").font(.footnote).foregroundStyle(Theme.textDim)
                        InfoButton(id: "pair-info", title: "Before you start", text: "Needs iOS 27 or later, Wi-Fi turned on, and the Local Network permission (iOS asks the first time).\n\n\(PairingCredits.text)")
                    }.padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
        }
        .onChange(of: isDone) { _, done in if done { scope.focused = "pair-main" } }
    }

    @State private var showDetails = false
    private var details: some View {
        SettingsGroup(title: "Troubleshooting") {
            ToggleRow(id: "pair-details", symbol: "ladybug.fill", title: "Show details", isOn: $showDetails)
            if showDetails {
                Text(pairing.trace.joined(separator: "\n")).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textDim).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                ActionRow(id: "pair-copy", symbol: "doc.on.doc", title: "Copy", chevron: false) { UIPasteboard.general.string = pairing.trace.joined(separator: "\n") }
            }
        }
    }

    private var unsupported: some View {
        SettingsGroup {
            ValueRow(id: "pair-unsupported", symbol: "exclamationmark.triangle.fill", title: "Needs iOS 27 or later", value: "")
            RowBase(id: "pair-older", symbol: "desktopcomputer", title: "On older versions", subtitle: "Make the file on a computer", info: "A pairing file has to be made on a computer with a pairing tool such as iloader or Jitterbug, then moved to this iPhone.", action: {}) { EmptyView() }
        }
    }

    private var steps: some View {
        SettingsGroup {
            step(1, "Press Start. Allow finding devices if iOS asks.", active: pairing.phase == .idle || pairing.phase == .starting)
            step(2, "Settings \u{203A} Privacy & Security \u{203A} Developer Mode \u{203A} \u{201C}Pair with \(OnDevicePairing.hostName)\u{201D}", active: pairing.phase == .waiting)
            step(3, "Type the six digits shown here", active: isShowingPIN)
            step(4, "Come back. The file is saved for you.", active: isDone)
        }
    }

    private func step(_ n: Int, _ text: String, active: Bool) -> some View {
        RowBase(id: "pair-step-\(n)", title: text, action: {}) {
            Text("\(n)").font(.footnote.weight(.bold)).foregroundStyle(active ? Theme.onAccent : Theme.textDim)
                .frame(width: 26, height: 26).background(active ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.panelHigh), in: Circle())
        }
        .opacity(active ? 1 : 0.6)
    }

    private var isShowingPIN: Bool { if case .showPIN = pairing.phase { true } else { false } }
    private var isDone: Bool { if case .success = pairing.phase { true } else { false } }

    @ViewBuilder private var status: some View {
        switch pairing.phase {
        case .idle: EmptyView()
        case .starting: HStack(spacing: 10) { ProgressView().tint(Theme.accent); Text("Starting\u{2026}").foregroundStyle(Theme.textDim) }.padding(.horizontal, 6)
        case .waiting:
            HStack(spacing: 10) { ProgressView().tint(Theme.accent); Text("Ready. Open Settings and tap \u{201C}Pair with \(OnDevicePairing.hostName)\u{201D}.").foregroundStyle(Theme.text) }.font(.subheadline).padding(.horizontal, 6)
        case .showPIN(let pin):
            VStack(spacing: 6) {
                Text("Type this code").font(.footnote).foregroundStyle(Theme.textDim)
                Text(pin).font(.system(size: 52, weight: .bold, design: .monospaced)).tracking(6).foregroundStyle(Theme.accent).shadow(color: Theme.accent.opacity(0.5 * Theme.glowStrength), radius: 12)
            }.frame(maxWidth: .infinity).padding(16).background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .success(let name):
            Label("Paired with \(name.trimmingCharacters(in: .whitespaces)). The file is saved.", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good).font(.subheadline.weight(.semibold)).padding(.horizontal, 6)
        case .failed(let why):
            Text(why).font(.subheadline).foregroundStyle(Theme.bad).padding(.horizontal, 6)
        }
    }

    @ViewBuilder private var controls: some View {
        switch pairing.phase {
        case .idle, .failed: PillButton(id: "pair-main", title: "Start", symbol: "play.fill", style: .primary) { pairing.start() }
        case .starting, .waiting, .showPIN: PillButton(id: "pair-main", title: "Cancel", symbol: "xmark") { pairing.cancel() }
        case .success: PillButton(id: "pair-main", title: "Done", symbol: "checkmark", style: .primary) { dismiss() }
        }
    }
}
