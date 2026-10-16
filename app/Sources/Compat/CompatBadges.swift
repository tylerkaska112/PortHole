// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

// The verdicts and badges compatibility reports are summed up into. Foundation only, so they can be tested on their own (app/Tests/Engine).

enum CompatVerdict: String, Codable, CaseIterable, Identifiable {
    case great, playable, broken
    var id: String { rawValue }
    var title: String {
        switch self { case .great: "Works great"; case .playable: "Works, with problems"; case .broken: "Doesn't work" }
    }
    /// For the small badge on a game card.
    var short: String {
        switch self { case .great: "Works great"; case .playable: "Playable"; case .broken: "Doesn't work" }
    }
    var detail: String {
        switch self {
        case .great: "Runs well from start to finish."
        case .playable: "Runs, but it is slow or has problems."
        case .broken: "Won't start, or crashes too often to play."
        }
    }
    var symbol: String {
        switch self { case .great: "checkmark.seal.fill"; case .playable: "exclamationmark.triangle.fill"; case .broken: "xmark.octagon.fill" }
    }
}

struct CompatVerdictInfo: Codable, Equatable {
    var verdict: CompatVerdict
    var reports: Int
    var confidence: String
}

/// Reports from other versions of the game engine: they are kept and readable, but they do not count toward a badge.
struct CompatEarlier: Codable, Equatable {
    var reports: Int
    /// How it ran on the engine reported on most recently before this one, the app version that last reported it, and when. Absent from an older server.
    var verdict: CompatVerdict?
    var engine: String?
    var appVersion: String?
    var date: String?
    var verdictReports: Int?
}

/// "Worked in v0.50.34": what the last earlier engine said, shown while nobody has reported on the current one. The engine mostly adds compatibility, so a game that worked then
/// usually still does; a game that did not work then may well work now, which is why this reads differently from a verdict.
struct CompatPast: Equatable {
    var verdict: CompatVerdict
    var version: String?
    var engine: String?

    private var where_: String { version.map { "v\($0)" } ?? "an earlier version" }
    var text: String {
        switch verdict { case .great: "Worked in \(where_)"; case .playable: "Somewhat worked in \(where_)"; case .broken: "Didn't work in \(where_)" }
    }
    var short: String {
        switch verdict { case .great: "Worked in"; case .playable: "Somewhat worked in"; case .broken: "Didn't work in" }
    }
    var symbol: String {
        switch verdict { case .great: "checkmark.circle.fill"; case .playable: "exclamationmark.circle.fill"; case .broken: "xmark.circle.fill" }
    }
    /// What this means, for the details.
    var explanation: String {
        switch verdict {
        case .great, .playable: "Reported on an earlier version of the game engine. Each engine update mostly adds support, so a game that ran then usually still does, but nobody has confirmed it on this version yet."
        case .broken: "Reported on an earlier version of the game engine. Engine updates mostly add support, so it may well run now, but nobody has confirmed it yet."
        }
    }
}

struct CompatBadge: Codable, Equatable {
    var overall: CompatVerdictInfo?
    var forDevice: CompatVerdictInfo?
    var verdict: CompatVerdict?
    var earlier: CompatEarlier?
    /// There are reports, but none on this engine yet: no badge until someone plays on it.
    var needsReview: Bool { verdict == nil && (earlier?.reports ?? 0) > 0 }
    /// How it ran on an earlier engine, while there is no verdict on this one.
    var past: CompatPast? {
        guard verdict == nil, let e = earlier, let v = e.verdict else { return nil }
        return CompatPast(verdict: v, version: e.appVersion, engine: e.engine)
    }
}

