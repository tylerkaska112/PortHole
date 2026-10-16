// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import LauncherCore

// launcher-sign: the Launcher's on-device signer, run on the Mac.
//
//   launcher-sign inspect App.ipa
//   launcher-sign sign App.ipa -o Signed.ipa --p12 cert.p12 --password-env P12_PASSWORD --profile a.mobileprovision [--profile b.mobileprovision]
//                   [--bundle-id com.x.y] [--name "Shown name"] [--strip-extensions] [--strip-watch] [--file-sharing]
//                   [--app-group-key WaylonAppGroup]
//   launcher-sign sign App.ipa -o Adhoc.ipa --adhoc      # no certificate: verifiable with `codesign --verify`, not installable

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    exit(1)
}

let allArguments = Array(CommandLine.arguments.dropFirst())
guard let command = allArguments.first else { fail("usage: launcher-sign inspect|sign <ipa> …") }
let arguments = Array(allArguments.dropFirst())

func value(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}
func values(after flag: String) -> [String] {
    arguments.indices.filter { arguments[$0] == flag && $0 + 1 < arguments.count }.map { arguments[$0 + 1] }
}

guard let input = arguments.first(where: { $0.hasSuffix(".ipa") && FileManager.default.fileExists(atPath: $0) }) else { fail("pass an existing .ipa") }
let ipa: Data
do { ipa = try Data(contentsOf: URL(fileURLWithPath: input)) } catch { fail("can't read \(input): \(error.localizedDescription)") }

switch command {
case "inspect":
    do {
        let info = try IPAInspector.inspect(ipa)
        print("\(info.name)  \(info.bundleID)  \(info.version) (\(info.build))  iOS ≥ \(info.minimumOS ?? "?")")
        print("signed: \(info.isSigned)   embedded profile: \(info.hasProfile)   size unpacked: \(info.uncompressedSize / 1_048_576) MB")
        for nested in info.nested { print("  \(nested.kind.rawValue): \(nested.path)\(nested.bundleID.map { "  (\($0))" } ?? "")") }
    } catch { fail(error.localizedDescription) }

case "sign":
    var identity: SigningIdentity?
    var profiles: [ProvisioningProfile] = []
    if !arguments.contains("--adhoc") {
        guard let p12Path = value(after: "--p12") else { fail("--p12 is required (or --adhoc)") }
        let password = value(after: "--password") ?? value(after: "--password-env").flatMap { ProcessInfo.processInfo.environment[$0] } ?? ""
        do {
            var loaded = try SigningIdentity(p12: Data(contentsOf: URL(fileURLWithPath: p12Path)), password: password)
            await loaded.completeChain()
            identity = loaded
            for path in values(after: "--profile") { profiles.append(try ProvisioningProfile(data: Data(contentsOf: URL(fileURLWithPath: path)))) }
        } catch { fail(error.localizedDescription) }
        if profiles.isEmpty { fail("at least one --profile is required") }
    }
    let options = SigningOptions(
        bundleID: value(after: "--bundle-id"), displayName: value(after: "--name"), stripExtensions: arguments.contains("--strip-extensions"),
        stripWatchApps: arguments.contains("--strip-watch"), enableFileSharing: arguments.contains("--file-sharing"),
        appGroupInfoKeys: values(after: "--app-group-key")
    )
    let output = value(after: "-o") ?? input.replacingOccurrences(of: ".ipa", with: "-signed.ipa")
    do {
        let adhocEntitlements: [String: Any]? = identity == nil ? ["application-identifier": "ADHOC.test", "get-task-allow": true] : nil
        let result = try IPASigner.sign(ipa: ipa, identity: identity, profiles: profiles, options: options, entitlements: adhocEntitlements) { print("▸ \($0)") }
        try result.ipa.write(to: URL(fileURLWithPath: output), options: .atomic)
        for bundle in result.bundles { print("  signed \(bundle.kind.rawValue) \(bundle.path.isEmpty ? "(app)" : bundle.path)  \(bundle.identifier)\(bundle.profileName.map { "  profile “\($0)”" } ?? "")") }
        for warning in result.warnings { print("  ⚠︎ \(warning)") }
        print("✓ \(output)  \(result.bundleID) \(result.version) (\(result.build))")
    } catch { fail(error.localizedDescription) }

default:
    fail("unknown command \(command)")
}
