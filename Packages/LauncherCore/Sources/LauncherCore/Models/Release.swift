// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// One published build of an app: what `versions.json` lists and `latest.json` describes. Decoded tolerantly — every server
/// writes a slightly different subset, and one odd field must never hide the whole list.
public struct Release: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String { file }
    public let version: String
    public let build: String
    public let file: String
    /// Where to download the IPA (absolute); filled in from the source when the server didn't send one.
    public var url: URL?
    public let size: Int?
    public let sha256: String?
    /// The maintainer's Ed25519 signature of this release (base64), when the server carries one. Checked by `InstallPipeline.releaseCheck`.
    public let signature: String?
    public let bundleID: String?
    public let minimumOS: String?
    public let publishedAt: Date?
    /// `true` when the server already signed it for a device (Waylon's Mac signing); the Launcher re-signs regardless.
    public let isSigned: Bool?
    public let summary: String
    public let added: [String]
    public let changed: [String]
    public let fixed: [String]

    public var buildNumber: Int { Int(build) ?? 0 }
    public var hasNotes: Bool { !summary.isEmpty || !added.isEmpty || !changed.isEmpty || !fixed.isEmpty }
    public var title: String { "\(version) (\(build))" }

    public init(version: String, build: String, file: String, url: URL? = nil, size: Int? = nil, sha256: String? = nil, signature: String? = nil, bundleID: String? = nil,
                minimumOS: String? = nil, publishedAt: Date? = nil, isSigned: Bool? = nil, summary: String = "", added: [String] = [],
                changed: [String] = [], fixed: [String] = []) {
        self.version = version; self.build = build; self.file = file; self.url = url; self.size = size; self.sha256 = sha256; self.signature = signature
        self.bundleID = bundleID; self.minimumOS = minimumOS; self.publishedAt = publishedAt; self.isSigned = isSigned
        self.summary = summary; self.added = added; self.changed = changed; self.fixed = fixed
    }

    private enum Keys: String, CodingKey {
        case version, build, file, url, size, sha256, signature, bundleId, minimumOS, publishedAt, signed, summary, notes, added, changed, fixed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        version = try c.decode(String.self, forKey: .version)
        file = try c.decode(String.self, forKey: .file)
        // `build` is a string in some servers' JSON and a number in others.
        if let text = try? c.decode(String.self, forKey: .build) { build = text }
        else if let number = try? c.decode(Int.self, forKey: .build) { build = String(number) }
        else { build = "0" }
        url = (try? c.decodeIfPresent(String.self, forKey: .url)).flatMap { $0 }.flatMap(URL.init(string:))
        size = try? c.decodeIfPresent(Int.self, forKey: .size)
        sha256 = (try? c.decodeIfPresent(String.self, forKey: .sha256)) ?? nil
        signature = (try? c.decodeIfPresent(String.self, forKey: .signature)) ?? nil
        bundleID = (try? c.decodeIfPresent(String.self, forKey: .bundleId)) ?? nil
        minimumOS = (try? c.decodeIfPresent(String.self, forKey: .minimumOS)) ?? nil
        publishedAt = (try? c.decodeIfPresent(String.self, forKey: .publishedAt)).flatMap { $0 }.flatMap(Release.parseDate)
        isSigned = (try? c.decodeIfPresent(Bool.self, forKey: .signed)) ?? nil
        // `latest.json` carries `notes`; `versions.json` carries `summary` plus the lists.
        summary = ((try? c.decodeIfPresent(String.self, forKey: .summary)) ?? nil) ?? ((try? c.decodeIfPresent(String.self, forKey: .notes)) ?? nil) ?? ""
        added = ((try? c.decodeIfPresent([String].self, forKey: .added)) ?? nil) ?? []
        changed = ((try? c.decodeIfPresent([String].self, forKey: .changed)) ?? nil) ?? []
        fixed = ((try? c.decodeIfPresent([String].self, forKey: .fixed)) ?? nil) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(version, forKey: .version); try c.encode(build, forKey: .build); try c.encode(file, forKey: .file)
        try c.encodeIfPresent(url?.absoluteString, forKey: .url); try c.encodeIfPresent(size, forKey: .size)
        try c.encodeIfPresent(sha256, forKey: .sha256); try c.encodeIfPresent(signature, forKey: .signature); try c.encodeIfPresent(bundleID, forKey: .bundleId)
        try c.encodeIfPresent(minimumOS, forKey: .minimumOS); try c.encodeIfPresent(isSigned, forKey: .signed)
        try c.encodeIfPresent(publishedAt.map { Release.dateFormatter.string(from: $0) }, forKey: .publishedAt)
        try c.encode(summary, forKey: .summary); try c.encode(added, forKey: .added)
        try c.encode(changed, forKey: .changed); try c.encode(fixed, forKey: .fixed)
    }

    // ISO-8601 with or without fractional seconds (servers write both).
    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    nonisolated(unsafe) private static let plainDateFormatter = ISO8601DateFormatter()
    static func parseDate(_ text: String) -> Date? { dateFormatter.date(from: text) ?? plainDateFormatter.date(from: text) }
}

/// Comparing versions the way people read them: 1.0.10 is newer than 1.0.9, and the build number breaks a tie.
public enum AppVersion {
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = components(lhs), r = components(rhs)
        for index in 0..<max(l.count, r.count) {
            let a = index < l.count ? l[index] : 0, b = index < r.count ? r[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        version.split { !$0.isNumber }.compactMap { Int($0) }
    }

    /// Is (version, build) newer than (installedVersion, installedBuild)?
    public static func isNewer(version: String, build: String, than installedVersion: String, installedBuild: String) -> Bool {
        switch compare(version, installedVersion) {
        case .orderedDescending: true
        case .orderedAscending: false
        case .orderedSame: (Int(build) ?? 0) > (Int(installedBuild) ?? 0)
        }
    }
}
