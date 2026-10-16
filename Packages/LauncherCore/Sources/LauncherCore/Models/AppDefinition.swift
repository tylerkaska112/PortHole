// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Where an app's builds come from.
public struct UpdateSource: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public var name: String
    /// The folder that answers `latest.json`, `versions.json` and `files/<name>.ipa` (…/updates).
    public var baseURL: URL

    public init(id: String, name: String, baseURL: URL) { self.id = id; self.name = name; self.baseURL = baseURL }
}

/// One app the Launcher looks after: how to find its builds and how to sign them.
public struct AppDefinition: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public var name: String
    /// The bundle id the installed app has (what a build must keep so iOS replaces it).
    public var bundleID: String
    public var sourceID: String
    /// SF Symbol shown when the app has no icon of its own.
    public var symbol: String
    /// Accent colour as a hex string (`#RRGGBB`).
    public var tintHex: String
    /// A URL scheme the app answers to, used to show "Installed" and an Open button (`nil` = unknown).
    public var urlScheme: String?
    /// Signing options kept per app.
    public var signing: AppSigningSettings
    public var isHidden: Bool
    /// Built in (cannot be removed) vs added by the person.
    public var isBuiltIn: Bool

    public init(id: String, name: String, bundleID: String, sourceID: String, symbol: String = "app.badge", tintHex: String = "#4C8DFF",
                urlScheme: String? = nil, signing: AppSigningSettings = AppSigningSettings(), isHidden: Bool = false, isBuiltIn: Bool = false) {
        self.id = id; self.name = name; self.bundleID = bundleID; self.sourceID = sourceID; self.symbol = symbol; self.tintHex = tintHex
        self.urlScheme = urlScheme; self.signing = signing; self.isHidden = isHidden; self.isBuiltIn = isBuiltIn
    }
}

/// What the signer does to one app, beyond signing it.
public struct AppSigningSettings: Codable, Sendable, Equatable, Hashable {
    /// Sign with a different bundle id (leave `nil` to keep the app's own).
    public var bundleIDOverride: String?
    public var displayNameOverride: String?
    public var stripExtensions = false
    /// Only these extensions are removed (folder names in PlugIns). Optional so a catalog saved before this existed still reads.
    public var stripExtensionNames: [String]?
    public var stripWatchApps = false
    public var enableFileSharing = false
    /// Info.plist keys that receive the profile's App Group (the app reads the group from there at runtime).
    public var appGroupInfoKeys: [String] = []
    /// A specific certificate / profile to use, by id, instead of the automatic choice.
    public var preferredCertificateID: String?
    public var preferredProfileID: String?

    public init(bundleIDOverride: String? = nil, displayNameOverride: String? = nil, stripExtensions: Bool = false, stripWatchApps: Bool = false,
                enableFileSharing: Bool = false, appGroupInfoKeys: [String] = [], preferredCertificateID: String? = nil, preferredProfileID: String? = nil,
                stripExtensionNames: [String]? = nil) {
        self.stripExtensionNames = stripExtensionNames
        self.bundleIDOverride = bundleIDOverride; self.displayNameOverride = displayNameOverride
        self.stripExtensions = stripExtensions; self.stripWatchApps = stripWatchApps; self.enableFileSharing = enableFileSharing
        self.appGroupInfoKeys = appGroupInfoKeys; self.preferredCertificateID = preferredCertificateID; self.preferredProfileID = preferredProfileID
    }

    public var isDefault: Bool { self == AppSigningSettings() }
}

/// What ships with the app. Nothing here is specific to one person: addresses come from `BuildIdentity`, and apps and servers are added in Settings.
public enum BuiltIn {
    /// Apps whose builds live on the Hub (this app itself, and anything registered there later).
    public static let hubSourceID = "hub"

    public static let sources: [UpdateSource] = []

    /// The Hub's address until the person changes it in Settings. `nil` when the build was made without one.
    public static var defaultHubURL: URL? { BuildIdentity.hubURL }

    public static let apps: [AppDefinition] = []

    /// This app itself: it updates from the Hub like anything else.
    public static var launcherApp: AppDefinition {
        AppDefinition(id: "launcher", name: "Porthole", bundleID: Bundle.main.bundleIdentifier ?? "site.portholehq.app", sourceID: hubSourceID,
                      symbol: "shippingbox.fill", tintHex: "#7C5CFF", isBuiltIn: true)
    }
}
