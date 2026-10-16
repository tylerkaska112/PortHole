// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import LauncherCore

/// Secrets (the signing certificate and its password, this install's report key) live in the Keychain only. The shared update code used to fall
/// back to a protected file when the Keychain refused, and a Windows program running inside Porthole can open any file the app can. Anything an earlier
/// version left in such a file is moved into the Keychain and the file is deleted; if the Keychain still refuses it, the file is deleted anyway and the
/// secret has to be entered again, which is better than leaving it where a program can read it.
enum SecretMigration {
    private static let keys = ["vault.v1", "compat.signing-key"]
    nonisolated(unsafe) private static var done = false

    static func run() {
        guard !done else { return }
        done = true
        let files = FileSecretStore(), keychain = KeychainSecretStore()
        var moved = 0
        for key in keys {
            guard let data = files.load(key) else { continue }
            if keychain.load(key) == nil { try? keychain.save(data, for: key) }
            files.remove(key)
            moved += 1
        }
        if moved > 0 { LogStore.shared.log("[secrets] \(moved) saved secret(s) moved from a file into the Keychain") }
        // Anything else left in that folder (an old copy under another name) goes too.
        let folder = FileStorage.defaultURL("Secrets")
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasSuffix(".secret") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}

/// The file picker hands the app a COPY of what was chosen, in the app's temporary folder, where a Windows program running inside Porthole can read it. A
/// pairing file or a certificate is read once and kept in the Keychain, so the copy is deleted straight away, and any left by an earlier version at app start.
enum SecretFiles {
    private static let extensions: Set<String> = ["p12", "pfx", "mobileprovision", "mobiledevicepairing", "plist"]

    /// Deletes `url` when it is inside the app's temporary folder (never a file the person keeps somewhere else).
    static func discard(_ url: URL) {
        let tmp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        guard url.resolvingSymlinksInPath().path.hasPrefix(tmp + "/") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Looks through the temporary folder (and the picker's Inbox in it) for certificate, profile and pairing files left behind.
    static func sweep() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        var removed = 0
        func clean(_ folder: URL, depth: Int) {
            for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] {
                let item = folder.appendingPathComponent(name)
                var isFolder: ObjCBool = false
                guard fm.fileExists(atPath: item.path, isDirectory: &isFolder) else { continue }
                if isFolder.boolValue { if depth < 2 { clean(item, depth: depth + 1) }; continue }
                if extensions.contains(item.pathExtension.lowercased()) { try? fm.removeItem(at: item); removed += 1 }
            }
        }
        clean(tmp, depth: 0)
        if removed > 0 { LogStore.shared.log("[secrets] \(removed) leftover copy(ies) of a certificate, profile or pairing file deleted") }
    }
}
