// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import Observation
import UIKit
import LauncherCore

/// Updating this app from inside itself: look for a newer build on the Hub, download it, sign it ON THIS DEVICE with the person's own certificate and
/// profile, and install it on this device. Nothing is uploaded. All of the work is done by LauncherCore (the Launcher's tested signer,
/// vault and pipeline); this class only registers the app with it.
@MainActor
@Observable
final class UpdateService {
    static let appID = Bundle.main.object(forInfoDictionaryKey: "PortholeHubAppID") as? String ?? "porthole"
    /// The bundle id inside the unsigned IPA we publish.
    /// The bundle id this build was made with (a signing service may have changed the one it runs under).
    static let projectBundleID = Bundle.main.object(forInfoDictionaryKey: "PortholeBuiltBundleID") as? String ?? Bundle.main.bundleIdentifier ?? "site.portholehq.app"

    /// The running instance, for Home Screen and remote-control links (`ShortcutRouter`).
    static weak var current: UpdateService?
    let settings: LauncherSettings
    let vault: CredentialVault
    let activity: ActivityLog
    let catalog: CatalogStore
    let pipeline: InstallPipeline

    let version: String
    let build: String
    var message: String?

    init() {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        version = v; build = b
        SecretMigration.run()
        // Keychain only: the file fallback is not used here (a Windows program inside the app could read it).
        let settings = LauncherSettings()
        let vault = CredentialVault(store: KeychainSecretStore())
        let activity = ActivityLog()
        let catalog = CatalogStore(settings: settings, transport: ProgressTransport(), selfBuild: (v, b))
        self.settings = settings; self.vault = vault; self.activity = activity; self.catalog = catalog
        pipeline = InstallPipeline(catalog: catalog, vault: vault, settings: settings, activity: activity)
        pipeline.deviceInstaller = OnDeviceInstaller()
        pipeline.releaseCheck = { app, release in ReleaseSignature.refusal(app: app, release: release) }
        registerSelf()
        Self.current = self
    }

    /// iOS replaces an app only when the new build has the INSTALLED bundle id. Whatever signing service installed this copy may have
    /// changed it, so updates are signed with the id of the copy that is running now.
    private func registerSelf() {
        let running = Bundle.main.bundleIdentifier ?? Self.projectBundleID
        var app = catalog.app(id: Self.appID)
            ?? AppDefinition(id: Self.appID, name: "Porthole", bundleID: running, sourceID: BuiltIn.hubSourceID, symbol: "gamecontroller.fill")
        app.bundleID = running
        app.signing.bundleIDOverride = running == Self.projectBundleID ? nil : running
        // An install made without some extensions (to spend fewer App IDs) is updated without them, or iOS would see a different app.
        let left = InstallCheck.missingExtensions
        app.signing.stripExtensionNames = left.isEmpty ? nil : left
        if catalog.app(id: Self.appID) == nil { catalog.addApp(app) } else { catalog.updateApp(app) }
    }

    var app: AppDefinition? { catalog.app(id: Self.appID) }
    var status: CatalogStore.AppStatus? { app.map { catalog.status(for: $0) } }
    /// A published build newer than this one, if any.
    var available: Release? {
        guard let latest = status?.latest, latest.buildNumber > (Int(build) ?? 0) else { return nil }
        return latest
    }

    func check() async {
        guard let app else { return }
        await catalog.refresh(app)
    }

    func startUpdate(_ release: Release) {
        guard let app else { return }
        pipeline.start(app: app, release: release)
    }
}
