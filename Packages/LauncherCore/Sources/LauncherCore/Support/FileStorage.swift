// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Where the app keeps its own files.
public enum FileStorage {
    /// `Application Support/<storage folder>/<name>`.
    public static func defaultURL(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(BuildIdentity.storageFolder, isDirectory: true).appendingPathComponent(name, isDirectory: true)
    }

    /// Downloaded and signed builds are big and can always be fetched again: the system may clear them.
    public static func cacheURL(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(BuildIdentity.storageFolder, isDirectory: true).appendingPathComponent(name, isDirectory: true)
    }
}

/// One Codable value kept as a JSON file (written atomically). Reading a damaged file gives the default instead of failing.
public struct JSONFile<Value: Codable & Sendable>: Sendable {
    public let url: URL
    public init(_ url: URL) { self.url = url }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch { /* a lost preference is not worth a crash */ }
    }
}
