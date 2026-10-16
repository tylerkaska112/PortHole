// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI
import LauncherCore

/// Covers the whole app while Porthole updates itself (download, sign with the person's certificate, install): the steps, the progress, and a plain warning not to
/// leave the app or close it, because leaving stops the update half way. Nothing underneath can be pressed until it is over; a finished or failed update is closed
/// with its button and the result stays on the Updates page.
struct UpdateProgressOverlay: View {
    @Environment(UpdateService.self) private var updates
    @State private var scope = FocusScope()
    @State private var closedJob: UUID?
    @Environment(\.scenePhase) private var scenePhase
    @State private var leftDuringUpdate = false

    private var job: InstallPipeline.Job? {
        // Only Porthole's own update: signing a file from Files (or another app) has its own page and does not take the screen.
        guard let job = updates.pipeline.job, job.appID == UpdateService.appID, job.id != closedJob else { return nil }
        return job
    }

    var body: some View {
        if let job {
            ZStack {
                Rectangle().fill(.regularMaterial).overlay(Color.black.opacity(0.5)).ignoresSafeArea()      // the page behind is blurred and dimmed, the card on it is solid
                    .contentShape(Rectangle())
                    .onTapGesture {}                                    // swallows touches: nothing below can be pressed
                card(job)
                    .padding(20)
                    .frame(maxWidth: 460)
            }
            .navScope(scope)
            .transition(.opacity)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = SteamStore.shared.isDownloading || EpicInstaller.shared.installs.values.contains { $0.isDownload }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active, !job.isFinished, !CellularGuard.shared.busy { leftDuringUpdate = true }        // a shortcut away is not the person leaving
                if phase == .active, job.isFinished { leftDuringUpdate = false }
            }
        }
    }

    // MARK: Card

    private func card(_ job: InstallPipeline.Job) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon(job)).font(.system(size: 40, weight: .bold)).foregroundStyle(tint(job))
            VStack(spacing: 4) {
                Text(heading(job)).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                Text(job.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textDim)
            }
            if !job.isFinished {
                if let question = CellularGuard.shared.hostedQuestion { cellularQuestion(question) }
                if let question = VPNGuard.shared.hostedQuestion { vpnQuestion(question) }
                steps(job)
                VStack(spacing: 8) {
                    ProgressView(value: overall(job)).tint(Theme.accent).scaleEffect(x: 1, y: 1.6)
                    HStack {
                        Text(stageText(job)).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(2)
                        Spacer(minLength: 8)
                        Text("\(Int((overall(job) * 100).rounded()))%").font(.system(size: 15, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Theme.accent)
                    }
                }
                warning
                PillButton(id: "upd-cancel", title: "Cancel the update", symbol: "xmark", style: .danger) { updates.pipeline.cancel() }
            } else {
                finished(job)
            }
        }
        .padding(22)
        // Solid, not glass: what is behind (the page, its rows) must not show through the words.
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.backgroundTop)
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.panel)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    /// Another VPN is on and Porthole's tunnel needs the one slot iOS has: asked here, in the popup, so the person does not have to find it elsewhere.
    private func vpnQuestion(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "network.badge.shield.half.filled").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pause your VPN?").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text)
                    Text(text).font(.footnote).foregroundStyle(Theme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                PillButton(id: "upd-vpn-yes", title: "Pause it", symbol: "pause.fill", style: .primary) { VPNGuard.shared.answerHosted(true) }
                PillButton(id: "upd-vpn-no", title: "Keep it on", symbol: "xmark") { VPNGuard.shared.answerHosted(false) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1.5))
        .onAppear { scope.defaultFocus = "upd-vpn-yes"; scope.focused = "upd-vpn-yes" }
    }

    /// Cellular data stops Porthole's private connection from working: asked here, in the popup, like the VPN question.
    private func cellularQuestion(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Switch cellular data off?").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text)
                    Text(text).font(.footnote).foregroundStyle(Theme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                PillButton(id: "upd-cell-yes", title: "Switch it off", symbol: "antenna.radiowaves.left.and.right.slash", style: .primary) { CellularGuard.shared.answerHosted(true) }
                PillButton(id: "upd-cell-no", title: "Keep it on", symbol: "xmark") { CellularGuard.shared.answerHosted(false) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1.5))
        .onAppear { scope.defaultFocus = "upd-cell-yes"; scope.focused = "upd-cell-yes" }
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.warn)
            VStack(alignment: .leading, spacing: 4) {
                Text("Keep Porthole open").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text)
                Text("Stay on this screen. Do not close the app, switch to another one or lock the phone until this says it is done, or the update stops half way.")
                    .font(.footnote).foregroundStyle(Theme.text.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                if leftDuringUpdate {
                    Text("You left the app for a moment. If the percentage below does not move, tap Cancel and start the update again.")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warn.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.warn.opacity(0.5), lineWidth: 1))
    }

    @ViewBuilder private func finished(_ job: InstallPipeline.Job) -> some View {
        switch job.phase {
        case .installed:
            Text("Porthole is installed. It restarts by itself; if it does not, open it from the Home Screen.").font(.subheadline).foregroundStyle(Theme.text.opacity(0.9)).multilineTextAlignment(.center)
        case .saved:
            Text("The new version was signed but this device could not install it by itself. The signed file is kept: Settings > Updates offers it to save or share.")
                .font(.subheadline).foregroundStyle(Theme.text.opacity(0.9)).multilineTextAlignment(.center)
        case .failed(let why):
            Text(why).font(.subheadline).foregroundStyle(Theme.bad).multilineTextAlignment(.center)
        default: EmptyView()
        }
        PillButton(id: "upd-close", title: "Close", symbol: "checkmark", style: .primary) { closedJob = job.id }
            .onAppear { scope.defaultFocus = "upd-close"; scope.focused = "upd-close" }
    }

    // MARK: Steps and progress

    private enum Step: Int, CaseIterable {
        case download, sign, install
        var title: String { switch self { case .download: "Download"; case .sign: "Sign"; case .install: "Install" } }
        var symbol: String { switch self { case .download: "arrow.down.circle.fill"; case .sign: "signature"; case .install: "iphone.gen3" } }
    }

    private func current(_ job: InstallPipeline.Job) -> Step {
        switch job.phase {
        case .downloading: .download
        case .signing: .sign
        default: .install
        }
    }

    private func steps(_ job: InstallPipeline.Job) -> some View {
        let now = current(job)
        return HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { step in
                let done = step.rawValue < now.rawValue, active = step == now
                HStack(spacing: 6) {
                    Image(systemName: done ? "checkmark.circle.fill" : step.symbol).font(.system(size: 14, weight: .bold))
                    Text(step.title).font(.system(size: 13, weight: active ? .heavy : .semibold, design: .rounded))
                }
                .foregroundStyle(done ? Theme.good : active ? Theme.accent : Theme.textDim)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background((active ? Theme.accent : Color.white).opacity(active ? 0.18 : 0.06), in: Capsule())
                if step != Step.allCases.last { Capsule().fill(Theme.line).frame(width: 10, height: 2) }
            }
        }
    }

    /// One bar for the whole trip: the download is the first 45%, signing the next 15%, and the install on this device the rest.
    private func overall(_ job: InstallPipeline.Job) -> Double {
        switch job.phase {
        case .downloading(let p): return 0.45 * min(max(p, 0), 1)
        case .signing: return 0.52
        case .installing(_, let p): return 0.60 + 0.40 * min(max(p, 0), 1)
        case .installed, .saved: return 1
        case .failed: return 0
        }
    }

    private func stageText(_ job: InstallPipeline.Job) -> String {
        switch job.phase {
        case .downloading(let p): return p > 0 ? "Downloading the new version \u{00B7} \(Int((p * 100).rounded()))%" : "Downloading the new version\u{2026}"
        case .signing(let step): return "Signing with your certificate \u{00B7} \(step)"
        case .installing(let stage, _): return "Installing \u{00B7} \(stage)"
        default: return ""
        }
    }

    private func heading(_ job: InstallPipeline.Job) -> String {
        switch job.phase {
        case .installed: "Installed"
        case .saved: "Signed, not installed"
        case .failed: "The update did not finish"
        default: job.kind == .downgrade ? "Going back to an older version" : "Updating Porthole"
        }
    }

    private func icon(_ job: InstallPipeline.Job) -> String {
        switch job.phase {
        case .installed: "checkmark.circle.fill"
        case .saved: "doc.badge.arrow.up.fill"
        case .failed: "xmark.octagon.fill"
        default: "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    private func tint(_ job: InstallPipeline.Job) -> Color {
        switch job.phase {
        case .installed: Theme.good
        case .saved: Theme.warn
        case .failed: Theme.bad
        default: Theme.accent
        }
    }
}
