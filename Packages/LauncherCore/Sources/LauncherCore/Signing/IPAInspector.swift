// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// What is inside an IPA, read without signing anything. Used to show the person what they are about to sign, to choose the
/// right profile, and to warn about things the signer can't fully guarantee.
public struct IPAInfo: Sendable, Equatable {
    public struct Nested: Sendable, Equatable, Identifiable {
        public enum Kind: String, Sendable { case framework, appExtension, watchApp, dylib }
        public var id: String { path }
        public let kind: Kind
        /// Path inside the app, e.g. `Frameworks/Turf.framework` or `PlugIns/TripWidget.appex`.
        public let path: String
        public let bundleID: String?
    }

    public let bundleID: String
    public let name: String
    public let version: String
    public let build: String
    public let minimumOS: String?
    public let executable: String
    public let nested: [Nested]
    /// `true` when the main executable already carries a code signature.
    public let isSigned: Bool
    /// `true` when an `embedded.mobileprovision` is present (it was signed for a device before).
    public let hasProfile: Bool
    /// Entitlement-ish facts from the Info.plist that affect signing.
    public let backgroundModes: [String]
    public let uncompressedSize: Int

    public var extensions: [Nested] { nested.filter { $0.kind == .appExtension } }
    public var frameworks: [Nested] { nested.filter { $0.kind == .framework } }
    public var watchApps: [Nested] { nested.filter { $0.kind == .watchApp } }
}

public enum IPAInspector {
    public static func inspect(_ ipa: Data) throws -> IPAInfo { try inspect(entries: try ZipArchive.read(ipa)) }

    static func inspect(entries: [ZipEntry]) throws -> IPAInfo {
        guard let root = BundleLayout.appRoot(in: entries) else { throw SigningError.badApp("no .app in Payload") }
        guard let infoEntry = entries.first(where: { $0.name == root + "Info.plist" }),
              let info = try PropertyListSerialization.propertyList(from: infoEntry.data, options: [], format: nil) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String,
              let executable = info["CFBundleExecutable"] as? String else {
            throw SigningError.badApp("no Info.plist or bundle identifier")
        }
        var nested: [IPAInfo.Nested] = []
        for bundle in BundleLayout.nestedBundles(in: entries, appRoot: root) {
            let relative = String(bundle.root.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let id = (try? BundleLayout.info(entries, at: bundle.root))?.dict["CFBundleIdentifier"] as? String
            let kind: IPAInfo.Nested.Kind = switch bundle.kind {
            case .framework: .framework
            case .appExtension: .appExtension
            case .app: .watchApp
            }
            nested.append(.init(kind: kind, path: relative, bundleID: id))
        }
        for dylib in BundleLayout.looseDylibs(in: entries, appRoot: root) {
            nested.append(.init(kind: .dylib, path: String(dylib.dropFirst(root.count)), bundleID: nil))
        }
        let main = entries.first { $0.name == root + executable }
        return IPAInfo(
            bundleID: bundleID,
            name: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? executable,
            version: info["CFBundleShortVersionString"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? "",
            minimumOS: info["MinimumOSVersion"] as? String,
            executable: executable,
            nested: nested,
            isSigned: main.map { (try? MachOImage($0.data))?.hasSignature ?? false } ?? false,
            hasProfile: entries.contains { $0.name == root + "embedded.mobileprovision" },
            backgroundModes: info["UIBackgroundModes"] as? [String] ?? [],
            uncompressedSize: entries.reduce(0) { $0 + $1.data.count }
        )
    }
}

/// Finding the parts of an app inside a zip's flat list of paths.
enum BundleLayout {
    struct NestedBundle: Equatable {
        enum Kind { case framework, appExtension, app }
        let root: String   // full path with trailing "/"
        let kind: Kind
        var depth: Int { root.split(separator: "/").count }
    }

    struct PlistFile {
        var dict: [String: Any]
        let isBinary: Bool
        let index: Int

        func serialized() throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: dict, format: isBinary ? .binary : .xml, options: 0)
        }
    }

    /// `Payload/Foo.app/` of the app in the archive.
    static func appRoot(in entries: [ZipEntry]) -> String? {
        if let direct = entries.first(where: { $0.name.hasPrefix("Payload/") && $0.name.hasSuffix(".app/") && $0.name.split(separator: "/").count == 2 })?.name { return direct }
        for entry in entries {
            let parts = entry.name.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count >= 3, parts[0] == "Payload", parts[1].hasSuffix(".app") { return "Payload/\(parts[1])/" }
        }
        return nil
    }

    /// Every framework, extension and nested app under the main app, found by path (an entry need not exist for the folder).
    static func nestedBundles(in entries: [ZipEntry], appRoot: String) -> [NestedBundle] {
        var seen = Set<String>()
        var result: [NestedBundle] = []
        for entry in entries where entry.name.hasPrefix(appRoot) && entry.name != appRoot {
            let relative = entry.name.dropFirst(appRoot.count)
            var path = appRoot
            let components = relative.split(separator: "/", omittingEmptySubsequences: true)
            for (index, component) in components.enumerated() {
                path += component + "/"
                // The last component of a file entry is the file itself, never a bundle.
                if index == components.count - 1 && !entry.isDirectory { break }
                let kind: NestedBundle.Kind?
                if component.hasSuffix(".framework") { kind = .framework }
                else if component.hasSuffix(".appex") { kind = .appExtension }
                else if component.hasSuffix(".app") { kind = .app }
                else { kind = nil }
                if let kind, seen.insert(path).inserted { result.append(NestedBundle(root: path, kind: kind)) }
            }
        }
        return result
    }

    /// `.dylib` files that belong to no nested bundle of their own: signed one by one.
    static func looseDylibs(in entries: [ZipEntry], appRoot: String) -> [String] {
        entries.filter { $0.name.hasPrefix(appRoot) && $0.name.hasSuffix(".dylib") && !$0.isDirectory && !$0.isSymlink }.map(\.name).sorted()
    }

    static func info(_ entries: [ZipEntry], at root: String) throws -> PlistFile {
        guard let index = entries.firstIndex(where: { $0.name == root + "Info.plist" }),
              let dict = try PropertyListSerialization.propertyList(from: entries[index].data, options: [], format: nil) as? [String: Any] else {
            throw SigningError.badApp("\(root) has no Info.plist")
        }
        return PlistFile(dict: dict, isBinary: entries[index].data.starts(with: Data("bplist".utf8)), index: index)
    }
}
