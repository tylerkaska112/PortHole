// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Picks, from everything the person imported, the provisioning profile that should sign a given bundle id.
///
/// Ranking (best first): a profile that names the bundle id exactly, then the longest wildcard that covers it; among equals the
/// one that lasts longest. A profile that has expired, or that doesn't list the signing certificate, is never chosen.
public struct ProfileMatcher: Sendable {
    public var profiles: [ProvisioningProfile]

    public init(_ profiles: [ProvisioningProfile]) { self.profiles = profiles }

    public func best(for bundleID: String, identity: SigningIdentity? = nil, now: Date = Date()) -> ProvisioningProfile? {
        candidates(for: bundleID, identity: identity, now: now).first
    }

    /// Every usable profile for `bundleID`, best first.
    public func candidates(for bundleID: String, identity: SigningIdentity? = nil, now: Date = Date()) -> [ProvisioningProfile] {
        profiles
            .filter { profile in
                guard profile.covers(bundleID: bundleID) else { return false }
                if let expiration = profile.expiration, expiration < now { return false }
                if let identity, !profile.certificateFingerprints.isEmpty, !profile.certificateFingerprints.contains(identity.fingerprint) { return false }
                return true
            }
            .sorted { lhs, rhs in
                let (l, r) = (specificity(lhs), specificity(rhs))
                if l != r { return l > r }
                return (lhs.expiration ?? .distantFuture) > (rhs.expiration ?? .distantFuture)
            }
    }

    /// Why nothing matched, in words a person can act on.
    public func explainMissing(for bundleID: String, identity: SigningIdentity? = nil, now: Date = Date()) -> String {
        if profiles.isEmpty { return "No provisioning profile has been imported yet." }
        let covering = profiles.filter { $0.covers(bundleID: bundleID) }
        if covering.isEmpty {
            let names = profiles.map { $0.applicationIdentifier }.joined(separator: ", ")
            return "None of your profiles covers \(bundleID) (you have: \(names))."
        }
        if covering.allSatisfy({ $0.isExpired }) { return "The profile for \(bundleID) has expired." }
        if let identity, covering.allSatisfy({ !$0.certificateFingerprints.isEmpty && !$0.certificateFingerprints.contains(identity.fingerprint) }) {
            return "The profile for \(bundleID) doesn't include the selected certificate."
        }
        return "No usable profile for \(bundleID)."
    }

    /// Higher = more specific: an exact id beats any wildcard, a longer wildcard prefix beats a shorter one.
    private func specificity(_ profile: ProvisioningProfile) -> Int {
        profile.explicitBundleID != nil ? Int.max : profile.applicationIdentifier.count
    }
}
