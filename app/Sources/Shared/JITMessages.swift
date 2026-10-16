// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import CryptoKit

/// Host -> helper. The helper runs in its own process because a process cannot attach a debugger to itself.
@objc(F4JITWorker)
protocol F4JITWorker {
    /// Attach to `pid` (the host), enable JIT for it, run the script until the host asks it to detach.
    func enable(_ pid: Int32, pairing: Data)
}

/// Helper -> host: progress for the UI, and the end result (nil = success).
@objc(F4JITHost)
protocol F4JITHost {
    func preparation(_ stage: String)
    func finished(_ error: String?)
}

enum JITPairing {
    /// A pairing file is a property list with the device identifier and a matching Ed25519 key pair. Checking it here gives a clear error at import time
    /// instead of an opaque failure from the debugger connection later.
    static func validate(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 1024 * 1024,
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let identifier = plist["identifier"] as? String, !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let publicKey = plist["public_key"] as? Data, publicKey.count == 32,
              let privateKey = plist["private_key"] as? Data, privateKey.count == 32,
              let signing = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKey),
              signing.publicKey.rawRepresentation == publicKey
        else { throw CocoaError(.fileReadCorruptFile) }
    }
}
