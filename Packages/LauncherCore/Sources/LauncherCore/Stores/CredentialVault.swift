// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import Observation

/// What is saved: certificates with their passwords, and provisioning profiles. One secret item, never in the repo.
struct StoredVault: Codable, Equatable {
    struct Certificate: Codable, Equatable, Identifiable { var id: String; var label: String; var p12: Data; var password: String; var addedAt: Date }
    struct Profile: Codable, Equatable, Identifiable { var id: String; var raw: Data; var addedAt: Date }
    var certificates: [Certificate] = []
    var profiles: [Profile] = []
}

/// Something about the signing material that needs attention.
public struct VaultProblem: Sendable, Equatable, Identifiable {
    public enum Severity: Int, Sendable, Comparable {
        case notice, warning, blocking
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    public var id: String { subject + message }
    public let severity: Severity
    public let subject: String
    public let message: String
    public let date: Date?
}

/// What the signer will use for one app.
public struct SigningSelection: @unchecked Sendable {
    public let identity: SigningIdentity
    public let certificateID: String
    /// Every usable profile that lists the chosen certificate, the person's preferred one first.
    public let profiles: [ProvisioningProfile]
    public let matcher: ProfileMatcher
}

/// The person's certificates and provisioning profiles (as many as they have), kept in the Keychain, and the logic that decides
/// which pair signs which app. A certificate never leaves the device.
@MainActor
@Observable
public final class CredentialVault {
    public struct CertificateEntry: Identifiable, @unchecked Sendable {
        public let id: String
        public var label: String
        public let identity: SigningIdentity
        public let addedAt: Date
    }

    public struct ProfileEntry: Identifiable, Sendable {
        public let id: String
        public let profile: ProvisioningProfile
        public let addedAt: Date
    }

    public private(set) var certificates: [CertificateEntry] = []
    public private(set) var profiles: [ProfileEntry] = []
    /// Stored items that could no longer be opened (a certificate whose file was damaged, say).
    public private(set) var unreadable: [String] = []

    private let store: any SecretStore
    private static let key = "vault.v1"
    private var stored = StoredVault()

    public init(store: any SecretStore = ResilientSecretStore()) {
        self.store = store
        load()
    }

    public var isEmpty: Bool { certificates.isEmpty && profiles.isEmpty }
    public var canSign: Bool { !certificates.isEmpty && !profiles.isEmpty }

    // MARK: Importing

    /// Adds a certificate. The same certificate imported again replaces the earlier copy (new password, say).
    @discardableResult
    public func importCertificate(_ p12: Data, password: String, label: String? = nil) throws -> CertificateEntry {
        let identity = try SigningIdentity(p12: p12, password: password)
        let id = identity.fingerprint.map { String(format: "%02x", $0) }.joined()
        let entry = CertificateEntry(id: id, label: label?.isEmpty == false ? label! : identity.commonName, identity: identity, addedAt: Date())
        stored.certificates.removeAll { $0.id == id }
        stored.certificates.append(.init(id: id, label: entry.label, p12: p12, password: password, addedAt: entry.addedAt))
        certificates.removeAll { $0.id == id }
        certificates.append(entry)
        try persist()
        return entry
    }

    @discardableResult
    public func importProfile(_ data: Data) throws -> ProfileEntry {
        let profile = try ProvisioningProfile(data: data)
        let id = profile.uuid.isEmpty ? UUID().uuidString : profile.uuid
        let entry = ProfileEntry(id: id, profile: profile, addedAt: Date())
        stored.profiles.removeAll { $0.id == id }
        stored.profiles.append(.init(id: id, raw: data, addedAt: entry.addedAt))
        profiles.removeAll { $0.id == id }
        profiles.append(entry)
        try persist()
        return entry
    }

    public func removeCertificate(id: String) {
        stored.certificates.removeAll { $0.id == id }
        certificates.removeAll { $0.id == id }
        try? persist()
    }

    public func removeProfile(id: String) {
        stored.profiles.removeAll { $0.id == id }
        profiles.removeAll { $0.id == id }
        try? persist()
    }

    public func renameCertificate(id: String, to label: String) {
        guard let index = certificates.firstIndex(where: { $0.id == id }), !label.isEmpty else { return }
        certificates[index].label = label
        if let s = stored.certificates.firstIndex(where: { $0.id == id }) { stored.certificates[s].label = label }
        try? persist()
    }

    /// Fills in the issuing certificates a `.p12` didn't carry (needs the network once) and keeps the completed chain in memory.
    public func completeChains(session: URLSession = .shared) async {
        for index in certificates.indices {
            var identity = certificates[index].identity
            await identity.completeChain(session: session)
            certificates[index] = CertificateEntry(id: certificates[index].id, label: certificates[index].label, identity: identity, addedAt: certificates[index].addedAt)
        }
    }

    // MARK: Choosing

    /// The certificate and profiles to sign `bundleID` with, or the reason there are none.
    public func selection(for bundleID: String, settings: AppSigningSettings = AppSigningSettings(), now: Date = Date()) -> Result<SigningSelection, SigningError> {
        let usableCertificates = certificates.filter { !$0.identity.isExpired }
        guard !certificates.isEmpty else { return .failure(.noProfile("Add a certificate (.p12) in Signing first.")) }
        guard !usableCertificates.isEmpty else { return .failure(.noProfile("Every certificate you added has expired.")) }
        guard !profiles.isEmpty else { return .failure(.noProfile("Add a provisioning profile (.mobileprovision) in Signing first.")) }

        let allProfiles = profiles.map(\.profile)
        let preferredProfile = settings.preferredProfileID.flatMap { id in profiles.first { $0.id == id }?.profile }

        // The certificate: the one asked for; otherwise the first whose profile covers this app; otherwise any usable one.
        let chosen: CertificateEntry
        if let id = settings.preferredCertificateID, let match = usableCertificates.first(where: { $0.id == id }) {
            chosen = match
        } else if let match = usableCertificates.first(where: { entry in
            ProfileMatcher(allProfiles).best(for: bundleID, identity: entry.identity, now: now) != nil
        }) {
            chosen = match
        } else {
            chosen = usableCertificates[0]
        }

        var usable = allProfiles.filter { profile in
            !profile.isExpired && (profile.certificateFingerprints.isEmpty || profile.certificateFingerprints.contains(chosen.identity.fingerprint))
        }
        if let preferredProfile, let index = usable.firstIndex(where: { $0.uuid == preferredProfile.uuid }) {
            usable.insert(usable.remove(at: index), at: 0)
        }
        guard !usable.isEmpty else {
            let matcher = ProfileMatcher(allProfiles)
            return .failure(.noProfile(matcher.explainMissing(for: bundleID, identity: chosen.identity, now: now)))
        }
        return .success(SigningSelection(identity: chosen.identity, certificateID: chosen.id, profiles: usable, matcher: ProfileMatcher(usable)))
    }

    // MARK: Health

    /// Everything about the signing material that needs attention, worst first. `warnWithinDays` flags what is about to expire.
    public func problems(warnWithinDays: Int = 7, now: Date = Date()) -> [VaultProblem] {
        var result: [VaultProblem] = []
        let horizon = now.addingTimeInterval(TimeInterval(warnWithinDays) * 86_400)
        for entry in certificates {
            if let end = entry.identity.notAfter {
                if end < now { result.append(.init(severity: .blocking, subject: entry.label, message: "The certificate has expired.", date: end)) }
                else if end < horizon { result.append(.init(severity: .warning, subject: entry.label, message: "The certificate expires soon.", date: end)) }
            }
        }
        for entry in profiles {
            let profile = entry.profile
            if let end = profile.expiration {
                if end < now { result.append(.init(severity: .blocking, subject: profile.name, message: "The profile has expired.", date: end)) }
                else if end < horizon { result.append(.init(severity: .warning, subject: profile.name, message: "The profile expires soon.", date: end)) }
            }
            if !profile.certificateFingerprints.isEmpty, !certificates.isEmpty,
               !certificates.contains(where: { profile.certificateFingerprints.contains($0.identity.fingerprint) }) {
                result.append(.init(severity: .warning, subject: profile.name, message: "None of your certificates is in this profile, so it can't be used.", date: nil))
            }
        }
        if certificates.isEmpty { result.append(.init(severity: .blocking, subject: "Certificate", message: "No certificate has been added.", date: nil)) }
        if profiles.isEmpty { result.append(.init(severity: .blocking, subject: "Profile", message: "No provisioning profile has been added.", date: nil)) }
        return result.sorted { $0.severity > $1.severity }
    }

    /// Does any of the profiles list this device? Only the profile's own list can say; the device id isn't readable by apps.
    public var teamIDs: Set<String> { Set(profiles.map(\.profile.teamID)) }

    // MARK: Persistence

    private func load() {
        guard let data = store.load(Self.key), let saved = try? JSONDecoder().decode(StoredVault.self, from: data) else { return }
        stored = saved
        for item in saved.certificates {
            if let identity = try? SigningIdentity(p12: item.p12, password: item.password) {
                certificates.append(CertificateEntry(id: item.id, label: item.label, identity: identity, addedAt: item.addedAt))
            } else { unreadable.append(item.label) }
        }
        for item in saved.profiles {
            if let profile = try? ProvisioningProfile(data: item.raw) { profiles.append(ProfileEntry(id: item.id, profile: profile, addedAt: item.addedAt)) }
            else { unreadable.append("a provisioning profile") }
        }
    }

    private func persist() throws {
        if stored == StoredVault() { store.remove(Self.key); return }
        let encoder = JSONEncoder()
        try store.save(try encoder.encode(stored), for: Self.key)
    }
}
