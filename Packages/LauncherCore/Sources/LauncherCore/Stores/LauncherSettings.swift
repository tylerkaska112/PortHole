// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import Observation

/// The app's own preferences, kept in UserDefaults.
@MainActor
@Observable
public final class LauncherSettings {
    private let defaults: UserDefaults

    public var hubURLString: String { didSet { defaults.set(hubURLString, forKey: "hubURL") } }
    /// How often to look for new builds while the app is open (minutes).
    public var checkIntervalMinutes: Int { didSet { defaults.set(checkIntervalMinutes, forKey: "checkIntervalMinutes") } }
    public var notifyAboutUpdates: Bool { didSet { defaults.set(notifyAboutUpdates, forKey: "notifyAboutUpdates") } }
    public var notifyAboutExpiry: Bool { didSet { defaults.set(notifyAboutExpiry, forKey: "notifyAboutExpiry") } }
    /// Warn this many days before a certificate or profile expires.
    public var expiryWarningDays: Int { didSet { defaults.set(expiryWarningDays, forKey: "expiryWarningDays") } }
    /// How many downloaded builds to keep on the device (so a re-install or downgrade needs no download).
    public var keptDownloads: Int { didSet { defaults.set(keptDownloads, forKey: "keptDownloads") } }
    /// Ask before downgrading an app.
    public var confirmDowngrades: Bool { didSet { defaults.set(confirmDowngrades, forKey: "confirmDowngrades") } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hubURLString = defaults.string(forKey: "hubURL") ?? BuiltIn.defaultHubURL?.absoluteString ?? ""
        checkIntervalMinutes = defaults.object(forKey: "checkIntervalMinutes") as? Int ?? 10
        notifyAboutUpdates = defaults.object(forKey: "notifyAboutUpdates") as? Bool ?? true
        notifyAboutExpiry = defaults.object(forKey: "notifyAboutExpiry") as? Bool ?? true
        expiryWarningDays = defaults.object(forKey: "expiryWarningDays") as? Int ?? 7
        keptDownloads = defaults.object(forKey: "keptDownloads") as? Int ?? 6
        confirmDowngrades = defaults.object(forKey: "confirmDowngrades") as? Bool ?? true
    }

    public var hubURL: URL? {
        let text = hubURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        // The Hub address carries the builds and the reports: https, except for this device itself (a test Hub on localhost).
        if scheme == "https" { return url }
        return scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host) ? url : nil
    }
}
