// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// What the app tells iOS about the game it runs, so the system treats it as the user's foreground work: an activity of the latency-critical, user-initiated kind for the
/// process, and the highest kernel latency and throughput tiers. After a minute or two of play iOS moved the game's busiest thread from the fast cores to the slow ones and
/// parked the fast cores at about 1.1 GHz even with the phone cold; none of these hints were being given. `env.PORTHOLE_SCHED_HINTS = 0` switches them off for a game.
@MainActor
enum SchedHints {
    private static var token: NSObjectProtocol?

    static func begin() {
        guard token == nil, EngineOptions.value("env.PORTHOLE_SCHED_HINTS") != "0" else { return }
        token = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled], reason: "Porthole is running a game")
        var latency: Int32 = 0, throughput: Int32 = 0
        _ = sched_hint_task_qos(&latency, &throughput)
        LogStore.shared.log("[sched] activity hint given; kernel latency tier result \(latency), throughput tier result \(throughput) (0 = accepted)")
    }

    static func end() {
        if let token { ProcessInfo.processInfo.endActivity(token) }
        token = nil
    }
}
