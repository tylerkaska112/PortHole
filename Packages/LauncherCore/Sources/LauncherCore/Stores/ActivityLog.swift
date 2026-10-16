// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import Observation

/// One thing the Launcher did: a signing, an install hand-off, a failure. The history answers "what did I install, when, and
/// with what?" and gives the detail to read when iOS refuses something.
public struct ActivityEntry: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case install, downgrade, signOnly, check, failure, info }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    public let appName: String
    public let bundleID: String?
    public let version: String?
    public let build: String?
    /// One line for the list.
    public let title: String
    /// The details: bundles signed, profiles used, warnings, timings, the error.
    public let detail: String
    public let succeeded: Bool

    public init(kind: Kind, appName: String, bundleID: String? = nil, version: String? = nil, build: String? = nil, title: String,
                detail: String = "", succeeded: Bool = true, date: Date = Date(), id: UUID = UUID()) {
        self.id = id; self.date = date; self.kind = kind; self.appName = appName; self.bundleID = bundleID
        self.version = version; self.build = build; self.title = title; self.detail = detail; self.succeeded = succeeded
    }
}

/// The recent activity, newest first, kept on disk (the last `limit` entries).
@MainActor
@Observable
public final class ActivityLog {
    public private(set) var entries: [ActivityEntry] = []
    private let file: JSONFile<[ActivityEntry]>?
    private let limit: Int

    public init(file: JSONFile<[ActivityEntry]>? = JSONFile(FileStorage.defaultURL("State").appendingPathComponent("activity.json")), limit: Int = 300) {
        self.file = file
        self.limit = limit
        entries = file?.load() ?? []
    }

    public func add(_ entry: ActivityEntry) {
        entries.insert(entry, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        file?.save(entries)
    }

    public func clear() {
        entries = []
        file?.save(entries)
    }

    public func entries(forBundleID bundleID: String) -> [ActivityEntry] { entries.filter { $0.bundleID == bundleID } }

    /// A plain-text report to paste into a chat or a note (what the pipeline did and why it failed).
    public func report(limit: Int = 20) -> String {
        entries.prefix(limit).map { entry in
            let when = entry.date.formatted(date: .abbreviated, time: .standard)
            return "[\(when)] \(entry.succeeded ? "OK" : "FAILED") \(entry.title)" + (entry.detail.isEmpty ? "" : "\n" + entry.detail.split(separator: "\n").map { "    \($0)" }.joined(separator: "\n"))
        }.joined(separator: "\n\n")
    }
}
