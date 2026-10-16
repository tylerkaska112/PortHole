// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Names and addresses that belong to whoever builds the app, not to the code. They come from the app's Info.plist (filled in from
/// `app/Config/Local.xcconfig`, which is not part of the repository), so a build made from this source contains nothing of its author's.
public enum BuildIdentity {
    private static func value(_ key: String) -> String? {
        guard let text = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unexpanded "$(NAME)" means the build setting was never defined.
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }

    /// Keychain service the app's secrets (certificates, the report-signing key) are filed under.
    public static var keychainService: String { value("PortholeKeychainService") ?? "site.portholehq.secrets" }
    /// Folder name inside Application Support and Caches.
    public static var storageFolder: String { value("PortholeStorageFolder") ?? "Porthole" }
    /// The server that updates and compatibility reports go to, until the person types another in Settings. Empty in a public build.
    public static var hubURL: URL? { value("PortholeHubURL").flatMap { URL(string: $0) }.flatMap { $0.scheme == nil ? nil : $0 } }
    /// Where this build's source code can be read online (the GPL source offer), if the person who built it set one.
    public static var sourceURL: URL? { value("PortholeSourceURL").flatMap { URL(string: $0) }.flatMap { $0.scheme == nil ? nil : $0 } }
}
