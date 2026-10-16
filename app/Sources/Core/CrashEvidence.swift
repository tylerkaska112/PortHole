// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// The logs of a run that ended while a game was running, kept safe.
///
/// Porthole starts a fresh log each time it opens and keeps only the one before it, and keeps the last 40 games' own logs. So if the app is opened again (or twice)
/// after a crash, the log that explains the crash is no longer "the previous log". When a launch finds that the last run ended unexpectedly, the crashed run's log
/// and the game's own log are put aside here (hard links, so nothing is copied), under a folder named for the time, and the three newest are kept. A problem report
/// then uses them, so it carries the crash and not the launch that followed it.
enum CrashEvidence {
    struct Record: Codable, Equatable {
        var game: String
        var started: Date
        var detected: Date
        var version: String
        var build: String
        var hasRunLog: Bool
        /// A log of the game's own that is not the same file as the run's log (a Steam game's, named by the engine).
        var hasGameLog: Bool
        var reported = false
    }

    private static let keep = 3

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CrashEvidence", isDirectory: true)
    }

    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    /// Called once, early in a launch, before anything starts a new game session.
    @MainActor static func captureIfNeeded() {
        guard let crash = CompatStore.shared.endedUnexpectedly else { return }
        // The log store rotates the finished run's log to madeira-log.prev.txt the first time it is touched in a launch. Touch it BEFORE reading that file, or
        // the file read is the run before the one that ended (a report made it look like the update's run had crashed).
        _ = LogStore.shared.logFileURL
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = DateFormatter(); stamp.dateFormat = "yyyyMMdd-HHmmss"; stamp.locale = Locale(identifier: "en_US_POSIX")
        let folder = directory.appendingPathComponent(stamp.string(from: Date()), isDirectory: true)
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch { return }

        func keepFile(_ source: URL, as name: String) -> Bool {
            let target = folder.appendingPathComponent(name)
            if (try? fm.linkItem(at: source, to: target)) != nil { return true }
            return (try? fm.copyItem(at: source, to: target)) != nil        // another volume, or links refused
        }
        // The crashed run's log is the one the app rotated aside when this launch began.
        let previous = docs.appendingPathComponent("madeira-log.prev.txt")
        let hasRun = fm.fileExists(atPath: previous.path) && keepFile(previous, as: "run.txt")
        // The game's own log: the newest file in logs/ that the crashed session was still writing.
        var hasGame = false
        let logs = docs.appendingPathComponent("logs", isDirectory: true)
        let candidates = ((try? fm.contentsOfDirectory(at: logs, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []).filter { $0.pathExtension == "txt" }
        if let newest = candidates.max(by: { modified($0) < modified($1) }), modified(newest) >= crash.started.addingTimeInterval(-10) {
            let sameAsRun = hasRun && sameFile(newest, folder.appendingPathComponent("run.txt"))
            if !sameAsRun { hasGame = keepFile(newest, as: "game.txt") }
        }
        let info = Bundle.main.infoDictionary
        let record = Record(game: crash.gameName, started: crash.started, detected: Date(), version: info?["CFBundleShortVersionString"] as? String ?? "?",
                            build: info?["CFBundleVersion"] as? String ?? "?", hasRunLog: hasRun, hasGameLog: hasGame)
        if let data = try? encoder.encode(record) { try? data.write(to: folder.appendingPathComponent("info.json")) }
        LogStore.shared.log("[crash] the last run ended while \(crash.gameName) was running; its log was kept (run \(hasRun ? "yes" : "no"), game's own \(hasGame ? "yes" : "same as the run"))")

        // Only the newest few are kept.
        let all = ((try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in all.dropFirst(keep) { try? fm.removeItem(at: old) }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func sameFile(_ a: URL, _ b: URL) -> Bool {
        guard let x = try? a.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let y = try? b.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else { return false }
        return x.isEqual(y)
    }

    // MARK: Reading

    struct Found {
        var record: Record
        var folder: URL
        var runLog: URL? { record.hasRunLog ? folder.appendingPathComponent("run.txt") : nil }
        var gameLog: URL? { record.hasGameLog ? folder.appendingPathComponent("game.txt") : nil }
    }

    /// The newest kept crash, if it has not been put into a report yet and is not too old to matter (a week).
    static func latestUnreported() -> Found? {
        let fm = FileManager.default
        let folders = ((try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent > $1.lastPathComponent }
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("info.json")), let record = try? decoder.decode(Record.self, from: data) else { continue }
            if record.reported || Date().timeIntervalSince(record.detected) > 7 * 24 * 3600 { return nil }
            return Found(record: record, folder: folder)
        }
        return nil
    }

    static func markReported(_ found: Found) {
        var record = found.record
        record.reported = true
        if let data = try? encoder.encode(record) { try? data.write(to: found.folder.appendingPathComponent("info.json")) }
    }
}
