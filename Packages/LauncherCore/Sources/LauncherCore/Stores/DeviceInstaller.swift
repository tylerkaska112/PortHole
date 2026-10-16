// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Installs a signed IPA on THIS device without any server in between (the app talks to iOS's own installer over the local tunnel).
/// The host app supplies one; LauncherCore has no idea how it works. When there is none, or it says no, the pipeline falls back to the Hub.
public protocol DeviceInstaller: Sendable {
    /// Can an install be attempted right now (a pairing file is present, the OS is new enough)?
    func isAvailable() async -> Bool
    /// Sends `ipa` to the installer and waits for iOS to finish. `progress` gets a short stage name and a 0…1 fraction.
    func install(ipa: URL, progress: @escaping @Sendable (String, Double) -> Void) async throws
}
