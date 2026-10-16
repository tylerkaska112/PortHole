// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import CryptoKit

/// Automatic save backups: after a game ends, the saves and settings (the same files as Settings > Saves > Back up) are zipped into `Documents/Saves backups`, which the Files
/// app shows. Only the newest few are kept, a backup is skipped when nothing has changed since the last one, and nothing is written when the saves are larger than a safe limit
/// or the phone is nearly out of space (a manual backup has no such limit).
enum AutoBackup {
    static let enabledKey = "f4.autoBackup"
    static let keep = 5
    static let maxSavesBytes = 150 << 20
    static let minFreeBytes: Int64 = 1 << 30
    private static let fingerprintKey = "f4.autoBackup.fingerprint"
    static let prefix = "Porthole-saves-auto"

    static func enabled(_ defaults: UserDefaults = .standard) -> Bool { defaults.object(forKey: enabledKey) as? Bool ?? true }
    static func setEnabled(_ on: Bool, _ defaults: UserDefaults = .standard) { defaults.set(on, forKey: enabledKey) }

    static var folder: URL { AppModel.documents.appendingPathComponent("Saves backups", isDirectory: true) }

    struct Entry: Identifiable, Equatable {
        let url: URL
        let date: Date
        let bytes: Int64
        var id: String { url.lastPathComponent }
    }

    enum Outcome: Equatable {
        case written(String), unchanged, noSaves, off, lowSpace
        case tooLarge(Int)               // bytes of saves
        case failed(String)

        var text: String {
            switch self {
            case .written(let name): "Backed up as \(name)."
            case .unchanged: "Nothing has changed since the last backup."
            case .noSaves: "There are no saves to back up yet."
            case .off: "Automatic backups are off."
            case .lowSpace: "Not enough free space to back up safely."
            case .tooLarge(let n): "The saves are \(ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)), more than an automatic backup keeps. Use Back up saves."
            case .failed(let why): "The backup failed: \(why)"
            }
        }
    }

    /// The automatic backups, newest first.
    static func entries(in directory: URL? = nil) -> [Entry] {
        let dir = directory ?? folder
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "zip" }.compactMap { url in
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return Entry(url: url, date: v?.contentModificationDate ?? .distantPast, bytes: Int64(v?.fileSize ?? 0))
        }.sorted { $0.date > $1.date }
    }

    /// A short digest of which files there are, how big and when they last changed.
    static func fingerprint(of items: [SaveBackup.Item]) -> String {
        var hasher = SHA256()
        for item in items.sorted(by: { $0.name < $1.name }) { hasher.update(data: Data("\(item.name)|\(item.size)|\(Int(item.modified))\n".utf8)) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func freeBytes(at url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? Int64.max
    }

    /// Runs once: scan, decide, write, prune. Synchronous (call it off the main thread). `force` ignores the "nothing changed" check.
    @discardableResult
    static func run(force: Bool = false, defaults: UserDefaults = .standard, directory: URL? = nil, freeSpace: (() -> Int64)? = nil, maxSaves: Int = maxSavesBytes) -> Outcome {
        guard enabled(defaults) || force else { return .off }
        let dir = directory ?? folder
        let scanned = SaveBackup.scan()
        guard !scanned.items.isEmpty else { return .noSaves }
        let total = scanned.items.reduce(0) { $0 + $1.size }
        guard total <= maxSaves, scanned.tooLarge == 0 else { return .tooLarge(total) }
        let print = fingerprint(of: scanned.items)
        if !force, defaults.string(forKey: fingerprintKey) == print, !entries(in: dir).isEmpty { return .unchanged }
        // The zip is about the size of the saves (stored, not compressed): leave room for it and a margin.
        guard (freeSpace?() ?? freeBytes(at: AppModel.documents)) > minFreeBytes + Int64(total) else { return .lowSpace }
        do {
            let result = try SaveBackup.backup(into: dir, namePrefix: prefix)
            defaults.set(print, forKey: fingerprintKey)
            prune(in: dir)
            return .written(result.url.lastPathComponent)
        } catch { return .failed(error.localizedDescription) }
    }

    static func prune(in directory: URL? = nil, keeping count: Int = keep) {
        for old in entries(in: directory).dropFirst(count) { try? FileManager.default.removeItem(at: old.url) }
    }

    static func deleteAll(in directory: URL? = nil, defaults: UserDefaults = .standard) {
        for e in entries(in: directory) { try? FileManager.default.removeItem(at: e.url) }
        defaults.removeObject(forKey: fingerprintKey)
    }

    /// After a game: a backup on a background queue, if they are on.
    static func afterSession() {
        guard enabled() else { return }
        DispatchQueue.global(qos: .utility).async {
            let outcome = run()
            if case .unchanged = outcome { return }
            LogStore.shared.log("[saves] automatic backup: \(outcome.text)")
        }
    }
}
