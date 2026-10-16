// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Testing
import Foundation
import CryptoKit
@testable import LauncherCore

/// Builds small but structurally real IPAs: thin arm64 Mach-O files the signer can really sign.
enum TestIPA {
    /// A minimal arm64 Mach-O: header, __TEXT, __LINKEDIT — the shape the linker makes, with no signature yet.
    static func machO(pages: Int = 3, fileType: UInt32 = 2) -> Data {
        var d = Data()
        func le32(_ v: UInt32) { d.le32(v) }
        func le64(_ v: UInt64) { d.le32(UInt32(v & 0xffffffff)); d.le32(UInt32(v >> 32)) }
        func name(_ s: String) { d.append(Data(s.utf8)); d.append(Data(count: 16 - s.utf8.count)) }
        let textSize = pages * 0x4000
        le32(0xfeedfacf); le32(0x0100000c); le32(0); le32(fileType); le32(2); le32(72 * 2 + 80); le32(0); le32(0)
        le32(0x19); le32(72 + 80); name("__TEXT"); le64(0x100000000); le64(UInt64(textSize)); le64(0); le64(UInt64(textSize)); le32(5); le32(5); le32(1); le32(0)
        name("__text"); name("__TEXT"); le64(0x100004000); le64(16); le32(0x4000); le32(2); le32(0); le32(0); le32(0x80000400); le32(0); le32(0); le32(0)
        le32(0x19); le32(72); name("__LINKEDIT"); le64(0x100000000 + UInt64(textSize)); le64(0x4000); le64(UInt64(textSize)); le64(100); le32(1); le32(1); le32(0); le32(0)
        d.append(Data(count: 0x4000 - d.count))
        for i in 0..<(textSize - 0x4000) { d.append(UInt8(i % 251)) }
        d.append(Data(repeating: 9, count: 100))
        return d
    }

    static func plist(_ dict: [String: Any]) throws -> Data { try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) }

    static func dir(_ name: String) -> ZipEntry { ZipEntry(name: name, mode: 0o40755) }

    /// `com.example.app` with a widget, two frameworks and a loose dylib, unless told otherwise.
    static func ipa(extensions: Bool = true, frameworks: Bool = true, dylib: Bool = true, extra: [ZipEntry] = []) throws -> Data {
        var entries: [ZipEntry] = [
            dir("Payload/"), dir("Payload/App.app/"),
            ZipEntry(name: "Payload/App.app/App", data: machO(), mode: 0o100755),
            ZipEntry(name: "Payload/App.app/Info.plist", data: try plist([
                "CFBundleIdentifier": "com.example.app", "CFBundleExecutable": "App", "CFBundleName": "App",
                "CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "9", "MinimumOSVersion": "17.0",
            ])),
            ZipEntry(name: "Payload/App.app/Assets.car", data: Data(repeating: 1, count: 1000)),
        ]
        if extensions {
            entries += [
                dir("Payload/App.app/PlugIns/"), dir("Payload/App.app/PlugIns/Widgets.appex/"),
                ZipEntry(name: "Payload/App.app/PlugIns/Widgets.appex/Widgets", data: machO(pages: 2), mode: 0o100755),
                ZipEntry(name: "Payload/App.app/PlugIns/Widgets.appex/Info.plist", data: try plist([
                    "CFBundleIdentifier": "com.example.app.widgets", "CFBundleExecutable": "Widgets", "CFBundleVersion": "9",
                    "NSExtension": ["NSExtensionPointIdentifier": "com.apple.widgetkit-extension"],
                ])),
            ]
        }
        if frameworks {
            for name in ["Alpha", "Beta"] {
                entries += [
                    dir("Payload/App.app/Frameworks/"), dir("Payload/App.app/Frameworks/\(name).framework/"),
                    ZipEntry(name: "Payload/App.app/Frameworks/\(name).framework/\(name)", data: machO(pages: 2, fileType: 6), mode: 0o100755),
                    ZipEntry(name: "Payload/App.app/Frameworks/\(name).framework/Info.plist", data: try plist([
                        "CFBundleIdentifier": "com.vendor.\(name.lowercased())", "CFBundleExecutable": name, "CFBundleVersion": "1",
                    ])),
                ]
            }
        }
        if dylib {
            entries.append(ZipEntry(name: "Payload/App.app/Frameworks/libhelper.dylib", data: machO(pages: 2, fileType: 6), mode: 0o100755))
        }
        return try ZipArchive.write(entries + extra)
    }

    static func profileData(appID: String, groups: [String] = [], name: String = "Test Profile", expires: String = "2099-01-01T00:00:00Z") -> Data {
        let groupsXML = groups.isEmpty ? "" : "<key>com.apple.security.application-groups</key><array>" + groups.map { "<string>\($0)</string>" }.joined() + "</array>"
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Name</key><string>\(name)</string><key>UUID</key><string>U-\(name)</string>
        <key>TeamIdentifier</key><array><string>TEAM123456</string></array>
        <key>ExpirationDate</key><date>\(expires)</date>
        <key>ProvisionedDevices</key><array><string>UDID1</string></array>
        <key>Entitlements</key><dict><key>application-identifier</key><string>\(appID)</string>
        <key>com.apple.developer.team-identifier</key><string>TEAM123456</string><key>get-task-allow</key><false/>\(groupsXML)</dict>
        </dict></plist>
        """
        return Data([0x30, 0x82, 0x01, 0x00]) + Data(plist.utf8) + Data([0x00, 0x01, 0x02])
    }

    static func profile(appID: String, groups: [String] = [], name: String = "Test Profile", expires: String = "2099-01-01T00:00:00Z") -> ProvisioningProfile {
        try! ProvisioningProfile(data: profileData(appID: appID, groups: groups, name: name, expires: expires))
    }

    static func info(_ entries: [ZipEntry], _ path: String) throws -> [String: Any] {
        let entry = try #require(entries.first { $0.name == path })
        return try #require(try PropertyListSerialization.propertyList(from: entry.data, options: [], format: nil) as? [String: Any])
    }

    static func isSigned(_ entries: [ZipEntry], _ path: String) throws -> Bool {
        let entry = try #require(entries.first { $0.name == path })
        return try MachOImage(entry.data).hasSignature
    }
}

@Suite("Signing an IPA with frameworks, extensions and libraries")
struct IPASignerTests {
    static let wildcard = TestIPA.profile(appID: "TEAM123456.*", name: "Wildcard")

    @Test func everyBundleGetsItsOwnSignatureAndSeal() throws {
        let result = try IPASigner.sign(ipa: try TestIPA.ipa(), identity: nil, profile: Self.wildcard)
        let entries = try ZipArchive.read(result.ipa)
        let names = Set(entries.map(\.name))
        let bundles = ["Payload/App.app/", "Payload/App.app/PlugIns/Widgets.appex/", "Payload/App.app/Frameworks/Alpha.framework/", "Payload/App.app/Frameworks/Beta.framework/"]
        for bundle in bundles { #expect(names.contains(bundle + "_CodeSignature/CodeResources"), "\(bundle) is sealed") }
        #expect(names.contains("Payload/App.app/embedded.mobileprovision") && names.contains("Payload/App.app/PlugIns/Widgets.appex/embedded.mobileprovision"))
        #expect(!names.contains("Payload/App.app/Frameworks/Alpha.framework/embedded.mobileprovision"), "frameworks carry no profile")
        for path in ["Payload/App.app/App", "Payload/App.app/PlugIns/Widgets.appex/Widgets", "Payload/App.app/Frameworks/Alpha.framework/Alpha",
                     "Payload/App.app/Frameworks/Beta.framework/Beta", "Payload/App.app/Frameworks/libhelper.dylib"] {
            #expect(try TestIPA.isSigned(entries, path), "\(path) is signed")
        }
        #expect(Set(result.bundles.map(\.kind)) == [.app, .appExtension, .framework, .dylib])
        #expect(result.bundleID == "com.example.app" && result.version == "1.2.3" && result.build == "9")
    }

    @Test func theAppSealCoversTheFinishedFilesOfWhatIsInsideIt() throws {
        let result = try IPASigner.sign(ipa: try TestIPA.ipa(), identity: nil, profile: Self.wildcard)
        let entries = try ZipArchive.read(result.ipa)
        let seal = try TestIPA.info(entries, "Payload/App.app/_CodeSignature/CodeResources")
        let files2 = try #require(seal["files2"] as? [String: Any])
        // The signed framework executable's hash is what the app's seal records — not the unsigned one.
        let executable = try #require(entries.first { $0.name == "Payload/App.app/Frameworks/Alpha.framework/Alpha" })
        let recorded = try #require((files2["Frameworks/Alpha.framework/Alpha"] as? [String: Any])?["hash2"] as? Data)
        #expect(recorded == Data(SHA256.hash(data: executable.data)))
        #expect(files2["Frameworks/Alpha.framework/_CodeSignature/CodeResources"] != nil)
    }

    @Test func aSecondSigningReplacesTheFirstInsteadOfStackingOnIt() throws {
        let first = try IPASigner.sign(ipa: try TestIPA.ipa(), identity: nil, profile: Self.wildcard)
        let second = try IPASigner.sign(ipa: first.ipa, identity: nil, profile: Self.wildcard)
        let names = try ZipArchive.read(second.ipa).map(\.name)
        #expect(names.filter { $0 == "Payload/App.app/embedded.mobileprovision" }.count == 1)
        #expect(names.filter { $0 == "Payload/App.app/_CodeSignature/CodeResources" }.count == 1)
    }

    @Test func renamingTheAppMovesItsExtensionsAlong() throws {
        let result = try IPASigner.sign(ipa: try TestIPA.ipa(), identity: nil, profile: Self.wildcard, options: SigningOptions(bundleID: "com.me.renamed"))
        let entries = try ZipArchive.read(result.ipa)
        #expect(try TestIPA.info(entries, "Payload/App.app/Info.plist")["CFBundleIdentifier"] as? String == "com.me.renamed")
        #expect(try TestIPA.info(entries, "Payload/App.app/PlugIns/Widgets.appex/Info.plist")["CFBundleIdentifier"] as? String == "com.me.renamed.widgets")
        #expect(try TestIPA.info(entries, "Payload/App.app/Frameworks/Alpha.framework/Info.plist")["CFBundleIdentifier"] as? String == "com.vendor.alpha", "frameworks keep their ids")
    }

    @Test func extensionsCanBeRemoved() throws {
        let result = try IPASigner.sign(ipa: try TestIPA.ipa(), identity: nil, profile: Self.wildcard, options: SigningOptions(stripExtensions: true))
        let names = try ZipArchive.read(result.ipa).map(\.name)
        #expect(!names.contains { $0.contains("PlugIns/") })
        #expect(result.bundles.allSatisfy { $0.kind != .appExtension })
    }

    @Test func onlyTheNamedExtensionsAreRemoved() throws {
        let removed = try IPASigner.sign(ipa: try TestIPA.ipa(), identity: nil, profile: Self.wildcard, options: SigningOptions(stripExtensionNames: ["Widgets.appex"]))
        #expect(!(try ZipArchive.read(removed.ipa).map(\.name)).contains { $0.contains("PlugIns/Widgets.appex") })
        let kept = try IPASigner.sign(ipa: try TestIPA.ipa(), identity: nil, profile: Self.wildcard, options: SigningOptions(stripExtensionNames: ["Other.appex"]))
        #expect((try ZipArchive.read(kept.ipa).map(\.name)).contains { $0.contains("PlugIns/Widgets.appex") })
    }

    @Test func theProfilesAppGroupIsWrittenIntoEveryInfoPlistThatAsksForIt() throws {
        let profile = TestIPA.profile(appID: "TEAM123456.*", groups: ["group.one", "group.two"])
        let result = try IPASigner.sign(ipa: try TestIPA.ipa(), identity: nil, profile: profile, options: SigningOptions(appGroupInfoKeys: ["MyAppGroup"]))
        let entries = try ZipArchive.read(result.ipa)
        #expect(try TestIPA.info(entries, "Payload/App.app/Info.plist")["MyAppGroup"] as? String == "group.one")
        #expect(try TestIPA.info(entries, "Payload/App.app/PlugIns/Widgets.appex/Info.plist")["MyAppGroup"] as? String == "group.one")
    }

    @Test func displayNameAndFileSharingAreApplied() throws {
        let result = try IPASigner.sign(ipa: try TestIPA.ipa(), identity: nil, profile: Self.wildcard, options: SigningOptions(displayName: "My App", enableFileSharing: true))
        let info = try TestIPA.info(try ZipArchive.read(result.ipa), "Payload/App.app/Info.plist")
        #expect(info["CFBundleDisplayName"] as? String == "My App")
        #expect(info["UIFileSharingEnabled"] as? Bool == true && info["LSSupportsOpeningDocumentsInPlace"] as? Bool == true)
    }

    @Test func eachBundleIsSignedWithTheProfileThatNamesIt() throws {
        let app = TestIPA.profile(appID: "TEAM123456.com.example.app", name: "App profile")
        let widget = TestIPA.profile(appID: "TEAM123456.com.example.app.widgets", name: "Widget profile")
        let result = try IPASigner.sign(ipa: try TestIPA.ipa(), identity: nil, profiles: [widget, app])
        #expect(result.warnings.isEmpty)
        #expect(result.bundles.first { $0.kind == .app }?.profileName == "App profile")
        #expect(result.bundles.first { $0.kind == .appExtension }?.profileName == "Widget profile")
    }

    @Test func anExtensionWithoutAMatchingProfileIsSignedAnywayWithAWarning() throws {
        let app = TestIPA.profile(appID: "TEAM123456.com.example.app", name: "App profile")
        let result = try IPASigner.sign(ipa: try TestIPA.ipa(), identity: nil, profiles: [app])
        #expect(result.warnings.count == 1 && result.warnings[0].contains("com.example.app.widgets"))
        #expect(result.bundles.first { $0.kind == .appExtension }?.profileName == "App profile")
    }

    @Test func anAppNoProfileCoversFallsBackToAnyValidOneWithAWarning() throws {
        let other = TestIPA.profile(appID: "TEAM123456.com.other.thing", name: "Other")
        let result = try IPASigner.sign(ipa: try TestIPA.ipa(extensions: false), identity: nil, profiles: [other])
        #expect(result.warnings.contains { $0.contains("com.example.app") })
        #expect(result.bundles.first { $0.kind == .app }?.profileName == "Other")
    }

    @Test func onlyExpiredProfilesIsAClearError() throws {
        let old = TestIPA.profile(appID: "TEAM123456.*", name: "Old", expires: "2001-01-01T00:00:00Z")
        #expect(throws: SigningError.self) { try IPASigner.sign(ipa: try TestIPA.ipa(), identity: nil, profiles: [old]) }
    }

    @Test func aPlainAppWithNothingNestedStillSigns() throws {
        let result = try IPASigner.sign(ipa: try TestIPA.ipa(extensions: false, frameworks: false, dylib: false), identity: nil, profile: Self.wildcard)
        #expect(result.bundles.map(\.kind) == [.app])
    }

    @Test func aRealCertificateSignsEverything() throws {
        let identity = try SigningIdentity(p12: SigningFixtures.p12, password: SigningFixtures.password)
        let result = try IPASigner.sign(ipa: try TestIPA.ipa(), identity: identity, profile: Self.wildcard)
        let entries = try ZipArchive.read(result.ipa)
        for path in ["Payload/App.app/App", "Payload/App.app/Frameworks/Beta.framework/Beta"] {
            let data = try #require(entries.first { $0.name == path }).data
            #expect(data.range(of: identity.leafDER) != nil, "\(path) carries the signer's certificate in its CMS signature")
            #expect(data.range(of: Data([0xfa, 0xde, 0x0c, 0xc0])) != nil, "\(path) has a code-signature SuperBlob")
        }
        // Ad hoc signing carries no certificate: the difference is what makes the test meaningful.
        let adhoc = try IPASigner.sign(ipa: try TestIPA.ipa(), identity: nil, profile: Self.wildcard)
        let adhocBinary = try #require(try ZipArchive.read(adhoc.ipa).first { $0.name == "Payload/App.app/App" }).data
        #expect(adhocBinary.range(of: identity.leafDER) == nil)
    }
}

@Suite("Choosing a profile")
struct ProfileMatcherTests {
    @Test func anExactProfileBeatsAWildcard() {
        let exact = TestIPA.profile(appID: "TEAM123456.com.a.b", name: "Exact")
        let wild = TestIPA.profile(appID: "TEAM123456.*", name: "Wild")
        #expect(ProfileMatcher([wild, exact]).best(for: "com.a.b")?.name == "Exact")
        #expect(ProfileMatcher([wild, exact]).best(for: "com.a.c")?.name == "Wild")
    }

    @Test func aLongerWildcardBeatsAShorterOne() {
        let broad = TestIPA.profile(appID: "TEAM123456.*", name: "Broad")
        let narrow = TestIPA.profile(appID: "TEAM123456.com.a.*", name: "Narrow")
        #expect(ProfileMatcher([broad, narrow]).best(for: "com.a.x")?.name == "Narrow")
    }

    @Test func expiredProfilesAreNeverChosen() {
        let old = TestIPA.profile(appID: "TEAM123456.com.a.b", name: "Old", expires: "2001-01-01T00:00:00Z")
        let fresh = TestIPA.profile(appID: "TEAM123456.*", name: "Fresh")
        #expect(ProfileMatcher([old, fresh]).best(for: "com.a.b")?.name == "Fresh")
        #expect(ProfileMatcher([old]).best(for: "com.a.b") == nil)
    }

    @Test func theMissingReasonIsSpecific() {
        #expect(ProfileMatcher([]).explainMissing(for: "com.a.b").contains("No provisioning profile"))
        let other = TestIPA.profile(appID: "TEAM123456.com.other", name: "Other")
        #expect(ProfileMatcher([other]).explainMissing(for: "com.a.b").contains("com.a.b"))
    }
}

@Suite("Inspecting an IPA")
struct IPAInspectorTests {
    @Test func itListsWhatIsInside() throws {
        let info = try IPAInspector.inspect(try TestIPA.ipa())
        #expect(info.bundleID == "com.example.app" && info.version == "1.2.3" && info.build == "9" && info.minimumOS == "17.0")
        #expect(info.extensions.map(\.bundleID) == ["com.example.app.widgets"])
        #expect(Set(info.frameworks.compactMap(\.bundleID)) == ["com.vendor.alpha", "com.vendor.beta"])
        #expect(info.nested.contains { $0.kind == .dylib && $0.path == "Frameworks/libhelper.dylib" })
        #expect(info.isSigned == false && info.hasProfile == false)
    }

    @Test func aSignedBuildIsRecognisedAsSigned() throws {
        let signed = try IPASigner.sign(ipa: try TestIPA.ipa(), identity: nil, profile: IPASignerTests.wildcard).ipa
        let info = try IPAInspector.inspect(signed)
        #expect(info.isSigned && info.hasProfile)
    }

    @Test func anArchiveWithoutAnAppIsRefused() throws {
        let zip = try ZipArchive.write([ZipEntry(name: "readme.txt", data: Data("hi".utf8))])
        #expect(throws: SigningError.self) { try IPAInspector.inspect(zip) }
    }
}
