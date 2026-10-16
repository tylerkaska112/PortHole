// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import CryptoKit
import LauncherCore

/// The maintainer signs every release with an Ed25519 key that never leaves their Mac (tools/release_sign.swift); the matching public key is built into the app
/// (`PORTHOLE_RELEASE_KEY` in Local.xcconfig). With it, an update is installed only when its signature is valid, so someone who gets at the update server cannot
/// hand this app a build of their own. The signature covers the app's name on the server, the version, the build number and the file's SHA-256, and the
/// download is checked against that SHA-256.
///
/// A build made without a key (someone building Porthole from source) does not check, because there is no maintainer key for it to trust.
enum ReleaseSignature {
    static var publicKey: Curve25519.Signing.PublicKey? {
        guard let text = Bundle.main.object(forInfoDictionaryKey: "PortholeReleaseKey") as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$("), let raw = Data(base64Encoded: trimmed) else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    static func message(app: String, version: String, build: String, sha256: String) -> Data {
        Data("porthole-release-v1\n\(app)\n\(version)\n\(build)\n\(sha256.lowercased())".utf8)
    }

    /// Why `release` must not be installed, or nil when it may be.
    static func refusal(app: String, release: Release, key: Curve25519.Signing.PublicKey?) -> String? {
        guard let key else { return nil }
        guard let sha = release.sha256, sha.count == 64 else { return "This update has no checksum, so it cannot be checked. It was not installed." }
        guard let text = release.signature, let signature = Data(base64Encoded: text) else {
            return "This update is not signed by the maintainer, so it was not installed. If you did not expect this, do not install it."
        }
        guard key.isValidSignature(signature, for: message(app: app, version: release.version, build: release.build, sha256: sha)) else {
            return "This update's signature is not valid, so it was not installed. The update server may have been tampered with."
        }
        return nil
    }

    static func refusal(app: AppDefinition, release: Release) -> String? { refusal(app: app.id, release: release, key: publicKey) }
}
