// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The download card: percentage, size, speed and time left on the lock screen and in the Dynamic Island, with Pause / Resume and Cancel buttons.
@main
struct PortholeActivityBundle: WidgetBundle {
    var body: some Widget { DownloadLiveActivity() }
}

struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            DownloadCard(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(Color(red: 0.10, green: 0.07, blue: 0.14))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.storeTitle, systemImage: "arrow.down.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(percent(context.state)).font(.title3.weight(.heavy)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressView(value: context.state.fraction).tint(cardTint(context.state))
                        Text(context.state.line).font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.8)
                        if !context.state.finished { Buttons(store: context.attributes.store, paused: context.state.paused) }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.paused ? "pause.circle.fill" : "arrow.down.circle.fill").foregroundStyle(cardTint(context.state))
            } compactTrailing: {
                Text(percent(context.state)).font(.caption.weight(.bold)).monospacedDigit()
            } minimal: {
                Image(systemName: context.state.paused ? "pause.circle.fill" : "arrow.down.circle.fill").foregroundStyle(cardTint(context.state))
            }
        }
    }
}

private func percent(_ state: DownloadActivityAttributes.ContentState) -> String {
    state.finished && !state.failed ? "Done" : "\(Int((state.fraction * 100).rounded()))%"
}

private func cardTint(_ state: DownloadActivityAttributes.ContentState) -> Color {
    state.failed ? .red : state.finished ? .green : state.paused ? .orange : Color(red: 1.0, green: 0.55, blue: 0.45)
}

private struct DownloadCard: View {
    let attributes: DownloadActivityAttributes
    let state: DownloadActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(attributes.storeTitle + (state.waiting > 0 ? " \u{00B7} +\(state.waiting) waiting" : "")).font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 8)
                Text(percent(state)).font(.title2.weight(.heavy)).monospacedDigit().foregroundStyle(cardTint(state))
            }
            ProgressView(value: state.fraction).tint(cardTint(state))
            Text(state.line).font(.footnote).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
            if !state.finished { Buttons(store: attributes.store, paused: state.paused) }
        }
    }
}

private struct Buttons: View {
    let store: String
    let paused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if paused {
                Button(intent: ResumeDownloadsIntent(store: store)) { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }
            } else {
                Button(intent: PauseDownloadsIntent(store: store)) { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }
            }
            Button(intent: CancelDownloadIntent(store: store)) { Label("Cancel", systemImage: "xmark").frame(maxWidth: .infinity) }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(.white)
    }
}
