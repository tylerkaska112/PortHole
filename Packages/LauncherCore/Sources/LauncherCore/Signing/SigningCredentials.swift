// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import Security
import CryptoKit

public enum SigningError: Error, LocalizedError, Equatable {
    case wrongPassword
    case badCertificateFile(String)
    case unsupportedKey
    case badProfile(String)
    case profileExpired(Date)
    case profileDoesNotMatchCertificate
    case profileDoesNotCoverApp(bundleID: String, profileAppID: String)
    case badApp(String)
    case unsupportedBinary(String)
    case signingFailed(String)
    case noProfile(String)

    public var errorDescription: String? {
        switch self {
        case .wrongPassword: "The certificate password is wrong."
        case .badCertificateFile(let detail): "Couldn't read that certificate file (\(detail))."
        case .unsupportedKey: "Only RSA signing certificates are supported."
        case .badProfile(let detail): "Couldn't read that provisioning profile (\(detail))."
        case .profileExpired(let date): "The provisioning profile expired on \(date.formatted(date: .abbreviated, time: .omitted))."
        case .profileDoesNotMatchCertificate: "That provisioning profile doesn't include your certificate — use the profile that came with it."
        case .profileDoesNotCoverApp(let bundle, let appID): "The profile is for \(appID), but the app is \(bundle)."
        case .badApp(let detail): "The app inside the IPA is unusual (\(detail))."
        case .unsupportedBinary(let detail): "Can't sign this build (\(detail))."
        case .signingFailed(let detail): "Signing failed (\(detail))."
        case .noProfile(let detail): detail
        }
    }
}

/// A `.mobileprovision` file: which app, which team, which devices, until when.
public struct ProvisioningProfile: Sendable, Equatable {
    public let raw: Data
    public let name: String
    public let uuid: String
    public let teamID: String
    /// `TEAMID.com.example.app`, or `TEAMID.*` for a wildcard profile.
    public let applicationIdentifier: String
    public let expiration: Date?
    /// UDIDs the build can be installed on; empty for enterprise ("all devices") profiles.
    public let provisionedDevices: [String]
    public let provisionsAllDevices: Bool
    public let getTaskAllow: Bool
    /// SHA-1 of each certificate the profile trusts.
    public let certificateFingerprints: [Data]
    /// App Group identifiers the profile allows (how an app and its extensions share files and settings).
    public let appGroups: [String]
    /// The profile's `Entitlements`, as an XML plist.
    let entitlementsPlist: Data

    public init(data: Data) throws {
        // A .mobileprovision is a CMS envelope around an XML plist: cut the plist out.
        guard let start = data.range(of: Data("<?xml".utf8)), let end = data.range(of: Data("</plist>".utf8), options: .backwards) else {
            throw SigningError.badProfile("no property list inside")
        }
        let plistData = data[start.lowerBound..<end.upperBound]
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let appID = entitlements["application-identifier"] as? String else {
            throw SigningError.badProfile("missing entitlements")
        }
        raw = data
        name = plist["Name"] as? String ?? "Provisioning profile"
        uuid = plist["UUID"] as? String ?? ""
        teamID = (plist["TeamIdentifier"] as? [String])?.first ?? (entitlements["com.apple.developer.team-identifier"] as? String) ?? String(appID.prefix { $0 != "." })
        applicationIdentifier = appID
        expiration = plist["ExpirationDate"] as? Date
        provisionedDevices = plist["ProvisionedDevices"] as? [String] ?? []
        provisionsAllDevices = plist["ProvisionsAllDevices"] as? Bool ?? false
        getTaskAllow = entitlements["get-task-allow"] as? Bool ?? false
        certificateFingerprints = (plist["DeveloperCertificates"] as? [Data] ?? []).map { Data(Insecure.SHA1.hash(data: $0)) }
        appGroups = entitlements["com.apple.security.application-groups"] as? [String] ?? []
        entitlementsPlist = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
    }

    public var isExpired: Bool { expiration.map { $0 < Date() } ?? false }

    private var entitlementDictionary: [String: Any] {
        (try? PropertyListSerialization.propertyList(from: entitlementsPlist, options: [], format: nil)) as? [String: Any] ?? [:]
    }

    /// Does the profile grant this boolean entitlement (for example `com.apple.developer.kernel.increased-memory-limit`)?
    public func grants(_ key: String) -> Bool { entitlementDictionary[key] as? Bool ?? false }

    /// The profile's list for an entitlement that holds one (Network Extensions, App Groups...); empty when it has none.
    public func stringValues(_ key: String) -> [String] { entitlementDictionary[key] as? [String] ?? [] }

    /// The one bundle id this profile is for (`nil` for a wildcard profile, which covers many).
    public var explicitBundleID: String? {
        guard !applicationIdentifier.hasSuffix("*"), applicationIdentifier.hasPrefix(teamID + ".") else { return nil }
        return String(applicationIdentifier.dropFirst(teamID.count + 1))
    }

    /// Does the profile cover this bundle id (exactly, or by a `TEAM.*` / `TEAM.prefix.*` wildcard)?
    public func covers(bundleID: String) -> Bool {
        let full = "\(teamID).\(bundleID)"
        if applicationIdentifier == full { return true }
        if applicationIdentifier.hasSuffix("*") { return full.hasPrefix(applicationIdentifier.dropLast()) }
        return false
    }

    /// The entitlements to sign with: the profile's, with a wildcard application identifier made concrete.
    func entitlements(for bundleID: String) throws -> [String: Any] {
        guard var entitlements = try PropertyListSerialization.propertyList(from: entitlementsPlist, options: [], format: nil) as? [String: Any] else {
            throw SigningError.badProfile("entitlements")
        }
        if applicationIdentifier.hasSuffix("*") { entitlements["application-identifier"] = "\(teamID).\(bundleID)" }
        return entitlements
    }
}

/// A signing certificate and its private key, imported from a `.p12`.
public struct SigningIdentity: @unchecked Sendable {
    let identity: SecIdentity
    let certificate: SecCertificate
    /// The leaf first, then whatever intermediates the file carried (DER).
    var chain: [Data]
    public let commonName: String
    public let notAfter: Date?
    /// SHA-1 of the certificate (what a provisioning profile lists).
    public let fingerprint: Data

    public var isExpired: Bool { notAfter.map { $0 < Date() } ?? false }
    var leafDER: Data { chain[0] }

    /// Imports a `.p12`. The key stays in memory; nothing is added to the Keychain.
    public init(p12: Data, password: String) throws {
        var options: [String: Any] = [kSecImportExportPassphrase as String: password]
        #if os(macOS)
        if #available(macOS 15.0, *) { options[kSecImportToMemoryOnly as String] = true }
        #endif
        var items: CFArray?
        let status = SecPKCS12Import(p12 as CFData, options as CFDictionary, &items)
        switch status {
        case errSecSuccess: break
        case errSecAuthFailed: throw SigningError.wrongPassword
        default: throw SigningError.badCertificateFile("error \(status)")
        }
        guard let first = (items as? [[String: Any]])?.first, let identityRef = first[kSecImportItemIdentity as String] else {
            throw SigningError.badCertificateFile("it has no signing identity")
        }
        let identity = identityRef as! SecIdentity // swiftlint:disable:this force_cast
        var certificateRef: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificateRef)
        guard let certificate = certificateRef else { throw SigningError.badCertificateFile("no certificate") }

        var others: [Data] = []
        for candidate in (first[kSecImportItemCertChain as String] as? [SecCertificate]) ?? [] {
            let der = SecCertificateCopyData(candidate) as Data
            if der != SecCertificateCopyData(certificate) as Data { others.append(der) }
        }
        let leaf = SecCertificateCopyData(certificate) as Data
        self.identity = identity
        self.certificate = certificate
        chain = [leaf] + others
        commonName = SecCertificateCopySubjectSummary(certificate) as String? ?? "Certificate"
        notAfter = CertificateFields(der: leaf)?.notAfter
        fingerprint = Data(Insecure.SHA1.hash(data: leaf))

        var key: SecKey?
        SecIdentityCopyPrivateKey(identity, &key)
        guard let key, (SecKeyCopyAttributes(key) as? [String: Any])?[kSecAttrKeyType as String] as? String == kSecAttrKeyTypeRSA as String else {
            throw SigningError.unsupportedKey
        }
    }

    /// RSA PKCS#1 v1.5 over SHA-256.
    func sign(_ message: Data) throws -> Data {
        var key: SecKey?
        SecIdentityCopyPrivateKey(identity, &key)
        guard let key else { throw SigningError.unsupportedKey }
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &error) as Data? else {
            throw SigningError.signingFailed(error?.takeRetainedValue().localizedDescription ?? "the key refused")
        }
        return signature
    }

    /// Adds the issuing certificates (Apple's intermediate and root) when the `.p12` didn't carry them. Without them iOS can't
    /// check the signature and quietly rolls the install back. Apple's are built in; anything else is downloaded from the
    /// address the certificate names.
    public mutating func completeChain(session: URLSession = .shared) async {
        chain = AppleCertificateAuthorities.completing(chain)
        var hops = 0
        while hops < 4, let last = chain.last, let fields = CertificateFields(der: last), !fields.isSelfIssued, let url = fields.issuerURL {
            var download = url
            if download.scheme == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) { parts.scheme = "https"; download = parts.url ?? url }   // iOS blocks plain http
            guard let (data, response) = try? await session.data(from: download), (response as? HTTPURLResponse)?.statusCode == 200,
                  SecCertificateCreateWithData(nil, data as CFData) != nil else { return }
            chain.append(data)
            hops += 1
        }
    }
}
