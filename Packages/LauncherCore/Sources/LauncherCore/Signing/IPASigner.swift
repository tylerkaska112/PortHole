// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import CryptoKit

/// Everything the person can ask the signer to do besides "sign it".
public struct SigningOptions: Sendable, Equatable {
    /// Rewrite the app's bundle identifier (its extensions follow, keeping the `<app id>.` prefix iOS requires).
    public var bundleID: String?
    /// Rewrite the name shown under the icon.
    public var displayName: String?
    /// Remove app extensions (widgets, Live Activities…). Use it when the profile names one exact app id and can't cover them.
    public var stripExtensions = false
    /// Remove only these app extensions, by their folder names inside PlugIns (for example `F4Tunnel.appex`). For an app that is installed without
    /// some of its extensions to save app ids: an update has to be signed the same way.
    public var stripExtensionNames: [String] = []
    /// Remove Watch apps.
    public var stripWatchApps = false
    /// Make the app's Documents folder visible in the Files app.
    public var enableFileSharing = false
    /// Info.plist keys that receive the profile's first App Group, so the app and its extensions agree on one.
    public var appGroupInfoKeys: [String] = []

    public init(bundleID: String? = nil, displayName: String? = nil, stripExtensions: Bool = false, stripWatchApps: Bool = false,
                enableFileSharing: Bool = false, appGroupInfoKeys: [String] = [], stripExtensionNames: [String] = []) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.stripExtensions = stripExtensions
        self.stripWatchApps = stripWatchApps
        self.enableFileSharing = enableFileSharing
        self.appGroupInfoKeys = appGroupInfoKeys
        self.stripExtensionNames = stripExtensionNames
    }
}

/// Re-signs an IPA on the device with the person's own certificate and provisioning profiles — the job `codesign` (or
/// Flarestore's signing) does on a Mac. Everything happens in memory; the certificate never leaves the device.
///
/// Signing order is deepest first, because each bundle's seal covers the finished files of everything inside it:
/// loose dylibs, then frameworks, then app extensions and Watch apps, and last the app itself.
public enum IPASigner {
    public struct SignedBundle: Sendable, Equatable {
        public enum Kind: String, Sendable { case app, framework, appExtension, watchApp, dylib }
        public let kind: Kind
        public let path: String
        public let identifier: String
        /// Name of the provisioning profile embedded in it (none for frameworks and dylibs).
        public let profileName: String?
    }

    public struct Result: Sendable {
        public let ipa: Data
        public let bundleID: String
        public let version: String
        public let build: String
        public let bundles: [SignedBundle]
        /// Things the signer had to guess, that may stop iOS from installing the result.
        public let warnings: [String]
    }

    public static func sign(
        ipa: Data, identity: SigningIdentity?, profile: ProvisioningProfile?, options: SigningOptions = SigningOptions(),
        entitlements: [String: Any]? = nil, progress: (@Sendable (String) -> Void)? = nil
    ) throws -> Result {
        try sign(ipa: ipa, identity: identity, profiles: profile.map { [$0] } ?? [], options: options, entitlements: entitlements, progress: progress)
    }

    /// - Parameters:
    ///   - identity: the certificate. `nil` signs ad hoc (verifiable on a Mac, not installable on a device — used by tests).
    ///   - profiles: every profile on hand; each bundle gets the best one for its own bundle id (see `ProfileMatcher`).
    ///   - entitlements: used only when there is no profile at all (tests).
    public static func sign(
        ipa: Data, identity: SigningIdentity?, profiles: [ProvisioningProfile], options: SigningOptions = SigningOptions(),
        entitlements: [String: Any]? = nil, progress: (@Sendable (String) -> Void)? = nil
    ) throws -> Result {
        progress?("Reading the app…")
        var entries = try ZipArchive.read(ipa)
        guard let root = BundleLayout.appRoot(in: entries) else { throw SigningError.badApp("no .app in Payload") }

        if options.stripExtensions { entries.removeAll { $0.name.hasPrefix(root + "PlugIns/") } }
        for name in options.stripExtensionNames where !name.isEmpty && !name.contains("/") {
            entries.removeAll { $0.name == root + "PlugIns/" + name || $0.name.hasPrefix(root + "PlugIns/" + name + "/") }
        }
        if options.stripWatchApps { entries.removeAll { $0.name.hasPrefix(root + "Watch/") || $0.name.hasPrefix(root + "com.apple.WatchPlaceholder/") } }

        let nested = BundleLayout.nestedBundles(in: entries, appRoot: root)
        let dylibs = BundleLayout.looseDylibs(in: entries, appRoot: root)

        // Anything left from an earlier signature goes (in the app and in every bundle inside it).
        for bundle in [root] + nested.map(\.root) {
            entries.removeAll { $0.name.hasPrefix(bundle + "_CodeSignature/") || $0.name == bundle + "embedded.mobileprovision" }
        }
        // Metadata some stores add that would be stale now.
        entries.removeAll { $0.name.hasPrefix(root + "SC_Info/") }

        var mainInfo = try BundleLayout.info(entries, at: root)
        guard let executableName = mainInfo.dict["CFBundleExecutable"] as? String,
              let originalID = mainInfo.dict["CFBundleIdentifier"] as? String else { throw SigningError.badApp("no bundle identifier or executable") }
        let finalID = options.bundleID.flatMap { $0.isEmpty ? nil : $0 } ?? originalID
        let matcher = ProfileMatcher(profiles)
        var warnings: [String] = []

        // The profile for the app itself: the best match, else any usable one (with a warning), else a clear error.
        var mainProfile: ProvisioningProfile?
        if !profiles.isEmpty {
            if let best = matcher.best(for: finalID, identity: identity) {
                mainProfile = best
            } else if let any = pickAny(profiles, identity: identity) {
                warnings.append("No profile covers \(finalID); signing with “\(any.name)” (for \(any.applicationIdentifier)) instead.")
                mainProfile = any
            } else {
                throw SigningError.noProfile(matcher.explainMissing(for: finalID, identity: identity))
            }
        }
        let teamID = mainProfile?.teamID
        let sharedGroup = mainProfile?.appGroups.first

        func patch(_ info: inout BundleLayout.PlistFile, isMain: Bool, renamedTo newID: String? = nil, touched: inout Bool) {
            if let newID, info.dict["CFBundleIdentifier"] as? String != newID { info.dict["CFBundleIdentifier"] = newID; touched = true }
            if let sharedGroup {
                for key in options.appGroupInfoKeys { info.dict[key] = sharedGroup; touched = true }
            }
            if isMain {
                if let name = options.displayName, !name.isEmpty { info.dict["CFBundleDisplayName"] = name; touched = true }
                if options.enableFileSharing {
                    info.dict["UIFileSharingEnabled"] = true
                    info.dict["LSSupportsOpeningDocumentsInPlace"] = true
                    touched = true
                }
            }
        }

        var signedBundles: [SignedBundle] = []
        let renamed = finalID != originalID

        // ---- 1. Loose dylibs: a bare signature, no resources, no profile.
        for path in dylibs {
            progress?("Signing \(path.split(separator: "/").last.map(String.init) ?? "a library")…")
            guard let index = entries.firstIndex(where: { $0.name == path }) else { continue }
            let identifier = (path.split(separator: "/").last.map(String.init) ?? path).replacingOccurrences(of: ".dylib", with: "")
            entries[index].data = try CodeSigner.sign(
                executable: entries[index].data,
                inputs: CodeSignatureInputs(identifier: identifier, teamID: teamID, infoPlist: nil, codeResources: nil, entitlements: nil, identity: identity, isMainExecutable: false)
            )
            entries[index].mode = 0o100755
            signedBundles.append(SignedBundle(kind: .dylib, path: String(path.dropFirst(root.count)), identifier: identifier, profileName: nil))
        }

        // ---- 2. Nested bundles, deepest first (a framework inside an extension before the extension).
        for bundle in nested.sorted(by: { $0.depth > $1.depth }) {
            let short = bundle.root.dropFirst(root.count).split(separator: "/").last.map(String.init) ?? "bundle"
            progress?("Signing \(short)…")
            var info = try BundleLayout.info(entries, at: bundle.root)
            guard let executable = info.dict["CFBundleExecutable"] as? String,
                  let originalNestedID = info.dict["CFBundleIdentifier"] as? String,
                  let executableIndex = entries.firstIndex(where: { $0.name == bundle.root + executable }) else {
                // A folder called *.framework / *.app without code (a resource bundle): it is sealed as plain files.
                continue
            }
            var nestedID = originalNestedID
            var touched = false
            if bundle.kind != .framework, renamed, originalNestedID.hasPrefix(originalID + ".") {
                nestedID = finalID + originalNestedID.dropFirst(originalID.count)
            }
            // A watch extension names its companion app; it must follow a rename.
            if renamed {
                for key in ["WKCompanionAppBundleIdentifier", "WKAppBundleIdentifier"] where info.dict[key] as? String == originalID {
                    info.dict[key] = finalID; touched = true
                }
            }
            patch(&info, isMain: false, renamedTo: bundle.kind == .framework ? nil : nestedID, touched: &touched)
            var infoBytes = entries[info.index].data
            if touched {
                infoBytes = try info.serialized()
                entries[info.index].data = infoBytes
            }

            var bundleEntitlements = entitlements
            var profileName: String?
            var bundleTeam = teamID
            if bundle.kind != .framework {
                if let nestedProfile = matcher.best(for: nestedID, identity: identity) ?? mainProfile {
                    if !nestedProfile.covers(bundleID: nestedID) {
                        warnings.append("No profile covers \(nestedID); it is signed with “\(nestedProfile.name)” (for \(nestedProfile.applicationIdentifier)). iOS may refuse the install — import a profile for it, or remove extensions in the app's signing options.")
                    }
                    bundleEntitlements = try nestedProfile.entitlements(for: nestedID)
                    bundleTeam = nestedProfile.teamID
                    profileName = nestedProfile.name
                    entries.append(ZipEntry(name: bundle.root + "embedded.mobileprovision", data: nestedProfile.raw))
                }
            } else {
                bundleEntitlements = nil
            }

            let resources = try codeResources(entries: entries, root: bundle.root, executable: bundle.root + executable)
            entries.append(ZipEntry(name: bundle.root + "_CodeSignature/", mode: 0o40755))
            entries.append(ZipEntry(name: bundle.root + "_CodeSignature/CodeResources", data: resources))
            entries[executableIndex].data = try CodeSigner.sign(
                executable: entries[executableIndex].data,
                inputs: CodeSignatureInputs(
                    identifier: nestedID, teamID: bundleTeam, infoPlist: infoBytes, codeResources: resources,
                    entitlements: bundleEntitlements, identity: identity, isMainExecutable: bundle.kind != .framework
                )
            )
            entries[executableIndex].mode = 0o100755
            let kind: SignedBundle.Kind = switch bundle.kind { case .framework: .framework; case .appExtension: .appExtension; case .app: .watchApp }
            signedBundles.append(SignedBundle(kind: kind, path: String(bundle.root.dropFirst(root.count)), identifier: nestedID, profileName: profileName))
        }

        // ---- 3. The app itself.
        var touched = false
        patch(&mainInfo, isMain: true, renamedTo: finalID, touched: &touched)
        var mainInfoBytes = entries[mainInfo.index].data
        if touched {
            mainInfoBytes = try mainInfo.serialized()
            entries[mainInfo.index].data = mainInfoBytes
        }
        var mainEntitlements = entitlements
        if let mainProfile {
            // Like ESign, Feather and zsign, the profile is used as it is: the app keeps its own bundle id (unless the caller
            // renames it) and is signed with the profile's entitlements, even when the profile names another app id.
            mainEntitlements = try mainProfile.entitlements(for: finalID)
            entries.append(ZipEntry(name: root + "embedded.mobileprovision", data: mainProfile.raw))
        }
        progress?("Sealing the app’s files…")
        guard let executableIndex = entries.firstIndex(where: { $0.name == root + executableName }) else { throw SigningError.badApp("the executable is missing") }
        let resources = try codeResources(entries: entries, root: root, executable: root + executableName)
        entries.append(ZipEntry(name: root + "_CodeSignature/", mode: 0o40755))
        entries.append(ZipEntry(name: root + "_CodeSignature/CodeResources", data: resources))
        progress?("Signing the app…")
        entries[executableIndex].data = try CodeSigner.sign(
            executable: entries[executableIndex].data,
            inputs: CodeSignatureInputs(
                identifier: finalID, teamID: teamID, infoPlist: mainInfoBytes, codeResources: resources,
                entitlements: mainEntitlements, identity: identity
            )
        )
        entries[executableIndex].mode = 0o100755
        signedBundles.append(SignedBundle(kind: .app, path: "", identifier: finalID, profileName: mainProfile?.name))

        progress?("Packing the IPA…")
        return Result(
            ipa: try ZipArchive.write(entries), bundleID: finalID,
            version: mainInfo.dict["CFBundleShortVersionString"] as? String ?? "", build: mainInfo.dict["CFBundleVersion"] as? String ?? "",
            bundles: signedBundles.reversed(), warnings: warnings
        )
    }

    /// Any profile that is still valid for the certificate, the longest-lasting first: the last resort when none names the app.
    private static func pickAny(_ profiles: [ProvisioningProfile], identity: SigningIdentity?) -> ProvisioningProfile? {
        profiles.filter { profile in
            !profile.isExpired && (identity == nil || profile.certificateFingerprints.isEmpty || profile.certificateFingerprints.contains(identity!.fingerprint))
        }.max { ($0.expiration ?? .distantFuture) < ($1.expiration ?? .distantFuture) }
    }

    // MARK: CodeResources

    /// `_CodeSignature/CodeResources`: a hash of every file in the bundle (except the executable, which has its own
    /// signature), in the format `codesign` writes.
    static func codeResources(entries: [ZipEntry], root: String, executable: String) throws -> Data {
        var files: [String: Any] = [:]
        var files2: [String: Any] = [:]
        for entry in entries.sorted(by: { $0.name < $1.name }) where entry.name.hasPrefix(root) && !entry.isDirectory {
            let path = String(entry.name.dropFirst(root.count))
            guard entry.name != executable, !path.hasPrefix("_CodeSignature/"), !path.hasSuffix("/.DS_Store"), path != ".DS_Store" else { continue }
            let optional = path.contains(".lproj/")
            let omitted = path.hasSuffix(".lproj/locversion.plist")

            if entry.isSymlink {
                let target = String(decoding: entry.data, as: UTF8.self)
                files[path] = ["symlink": target]
                files2[path] = ["symlink": target]
                continue
            }
            if !omitted {
                let sha1 = Data(Insecure.SHA1.hash(data: entry.data))
                files[path] = optional ? ["hash": sha1, "optional": true] as [String: Any] : sha1
            }
            if !omitted, path != "Info.plist", path != "PkgInfo" {
                var record: [String: Any] = ["hash2": Data(SHA256.hash(data: entry.data))]
                if optional { record["optional"] = true }
                files2[path] = record
            }
        }
        let plist: [String: Any] = ["files": files, "files2": files2, "rules": rules, "rules2": rules2]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    private static func rule(_ weight: Double, optional: Bool = false, omit: Bool = false) -> [String: Any] {
        var rule: [String: Any] = ["weight": weight]
        if optional { rule["optional"] = true }
        if omit { rule["omit"] = true }
        return rule
    }

    private static var rules: [String: Any] { [
        "^.*": true,
        "^.*\\.lproj/": rule(1000, optional: true),
        "^.*\\.lproj/locversion.plist$": rule(1100, omit: true),
        "^Base\\.lproj/": rule(1010),
        "^version.plist$": true,
    ] }

    private static var rules2: [String: Any] { [
        ".*\\.dSYM($|/)": rule(11),
        "^(.*/)?\\.DS_Store$": rule(2000, omit: true),
        "^.*": true,
        "^.*\\.lproj/": rule(1000, optional: true),
        "^.*\\.lproj/locversion.plist$": rule(1100, omit: true),
        "^Base\\.lproj/": rule(1010),
        "^Info\\.plist$": rule(20, omit: true),
        "^PkgInfo$": rule(20, omit: true),
        "^embedded\\.provisionprofile$": rule(20),
        "^version\\.plist$": rule(20),
    ] }
}
