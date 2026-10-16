// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import Observation

/// The apps the Launcher looks after, what each one's servers offer, and what the person has installed, skipped or held back.
@MainActor
@Observable
public final class CatalogStore {
    public enum LoadPhase: Equatable, Sendable { case idle, loading, loaded, failed(String) }

    public struct AppStatus: Equatable, Sendable {
        public var latest: Release?
        /// Every build on the server, newest first.
        public var releases: [Release] = []
        public var phase: LoadPhase = .idle
        public var checkedAt: Date?
    }

    /// What the Launcher knows about the copy on this device. iOS won't tell an app what other apps are installed, so this is
    /// the record of what the Launcher handed to the installer (or what the person typed in).
    public struct InstalledRecord: Codable, Equatable, Sendable {
        public enum Via: String, Codable, Sendable { case launcher, manual, this }
        public var version: String
        public var build: String
        public var installedAt: Date
        public var via: Via
        /// The team the build was signed with; a later build from another team is quietly refused by iOS.
        public var teamID: String?
    }

    struct Persisted: Codable, Equatable {
        var apps: [AppDefinition] = []
        var sources: [UpdateSource] = []
        var installed: [String: InstalledRecord] = [:]
        var skipped: [String: String] = [:]
        var held: [String: String] = [:]
    }

    public private(set) var apps: [AppDefinition]
    public private(set) var sources: [UpdateSource]
    public private(set) var status: [String: AppStatus] = [:]
    public private(set) var installed: [String: InstalledRecord] = [:]
    /// App id → the build the person chose to skip (a newer build is announced again).
    public private(set) var skipped: [String: String] = [:]
    /// App id → the build the person pinned: no update is offered while it is held.
    public private(set) var held: [String: String] = [:]
    public private(set) var lastRefreshed: Date?
    public private(set) var hubMessage: String?

    private let settings: LauncherSettings
    private let transport: any Transport
    private let file: JSONFile<Persisted>?
    /// This very copy of the Launcher: what the update check compares the Hub's newest build against.
    private let selfBuild: (version: String, build: String)?
    /// The apps and servers that come with the build (none in this source; tests pass their own).
    private let builtInApps: [AppDefinition]
    private let builtInSources: [UpdateSource]

    /// - Parameter stateURL: where the catalog is remembered (`nil` = not at all, for tests).
    public init(settings: LauncherSettings, transport: any Transport = URLSessionTransport(),
                stateURL: URL? = FileStorage.defaultURL("State").appendingPathComponent("catalog.json"),
                selfBuild: (version: String, build: String)? = nil,
                builtInApps: [AppDefinition] = BuiltIn.apps, builtInSources: [UpdateSource] = BuiltIn.sources) {
        self.builtInApps = builtInApps
        self.builtInSources = builtInSources
        self.settings = settings
        self.transport = transport
        let file = stateURL.map { JSONFile<Persisted>($0) }
        self.file = file
        self.selfBuild = selfBuild
        let saved = file?.load() ?? Persisted()
        // Built-in apps keep their addresses from the code; only what the person edited is taken from disk.
        var merged = builtInApps + [BuiltIn.launcherApp]
        for index in merged.indices {
            if let mine = saved.apps.first(where: { $0.id == merged[index].id }) {
                merged[index].signing = mine.signing
                merged[index].isHidden = mine.isHidden
                merged[index].urlScheme = mine.urlScheme
            }
        }
        apps = merged + saved.apps.filter { mine in !merged.contains { $0.id == mine.id } }
        sources = builtInSources + saved.sources.filter { mine in !builtInSources.contains { $0.id == mine.id } }
        installed = saved.installed
        skipped = saved.skipped
        held = saved.held
    }

    // MARK: Looking at apps

    public var visibleApps: [AppDefinition] { apps.filter { !$0.isHidden } }
    public func app(id: String) -> AppDefinition? { apps.first { $0.id == id } }
    public func status(for app: AppDefinition) -> AppStatus { status[app.id] ?? AppStatus() }
    public func source(id: String) -> UpdateSource? { sources.first { $0.id == id } }

    /// What is installed, as far as the Launcher knows. The Launcher itself always knows its own version.
    public func installedRecord(for app: AppDefinition) -> InstalledRecord? {
        if app.id == BuiltIn.launcherApp.id, let selfBuild {
            return InstalledRecord(version: selfBuild.version, build: selfBuild.build, installedAt: installed[app.id]?.installedAt ?? Date(), via: .this, teamID: installed[app.id]?.teamID)
        }
        return installed[app.id]
    }

    /// The newest build, if it is newer than what is installed and the person hasn't skipped or held it.
    public func availableUpdate(for app: AppDefinition) -> Release? {
        guard let latest = status(for: app).latest, held[app.id] == nil, skipped[app.id] != latest.build else { return nil }
        guard let record = installedRecord(for: app) else { return nil }
        return AppVersion.isNewer(version: latest.version, build: latest.build, than: record.version, installedBuild: record.build) ? latest : nil
    }

    /// The newest build, ignoring skip and hold — for showing "what's new" and the "Update" button the person asked for.
    public func newestIfNewer(for app: AppDefinition) -> Release? {
        guard let latest = status(for: app).latest else { return nil }
        guard let record = installedRecord(for: app) else { return latest }
        return AppVersion.isNewer(version: latest.version, build: latest.build, than: record.version, installedBuild: record.build) ? latest : nil
    }

    public var updateCount: Int { visibleApps.filter { availableUpdate(for: $0) != nil }.count }

    /// Everything that changed after the installed build, up to `through` (the newest by default): what an update brings.
    public func changes(for app: AppDefinition, through release: Release? = nil) -> [Release] {
        let all = status(for: app).releases
        guard let record = installedRecord(for: app) else { return all.filter { $0.hasNotes } }
        let ceiling = release?.buildNumber ?? Int.max
        return all.filter { $0.buildNumber > (Int(record.build) ?? 0) && $0.buildNumber <= ceiling }
    }

    /// Is `release` older than what is installed?
    public func isDowngrade(_ release: Release, for app: AppDefinition) -> Bool {
        guard let record = installedRecord(for: app) else { return false }
        return AppVersion.isNewer(version: record.version, build: record.build, than: release.version, installedBuild: release.build)
    }

    public func isInstalled(_ release: Release, for app: AppDefinition) -> Bool {
        guard let record = installedRecord(for: app) else { return false }
        return record.build == release.build && AppVersion.compare(record.version, release.version) == .orderedSame
    }

    // MARK: Fetching

    public func client(for app: AppDefinition) -> UpdatesClient? {
        if app.sourceID == BuiltIn.hubSourceID { return hub()?.updates(forApp: app.id) }
        return source(id: app.sourceID).map { UpdatesClient(baseURL: $0.baseURL, transport: transport) }
    }

    public func hub() -> HubClient? {
        settings.hubURL.map { HubClient(baseURL: $0, transport: transport) }
    }

    /// Looks at one app's server. A failure is kept with the app (the list shows it) and never stops the others.
    public func refresh(_ app: AppDefinition) async {
        var current = status[app.id] ?? AppStatus()
        guard let client = client(for: app) else {
            current.phase = .failed(app.sourceID == BuiltIn.hubSourceID ? "This build has no update server set." : "This app's source is missing.")
            status[app.id] = current
            return
        }
        if current.phase != .loaded { current.phase = .loading }
        status[app.id] = current
        do {
            let newest = try await client.latest()
            let list = try await client.versions()
            var releases = list
            // `latest.json` can name a build `versions.json` lacks (the history is rebuilt on publish): keep both.
            if let newest, !releases.contains(where: { $0.file == newest.file }) { releases.insert(newest, at: 0) }
            status[app.id] = AppStatus(latest: newest ?? releases.first, releases: releases, phase: .loaded, checkedAt: Date())
        } catch {
            var failed = status[app.id] ?? AppStatus()
            failed.phase = .failed(error.localizedDescription)
            status[app.id] = failed
        }
    }

    public func refreshAll() async {
        let snapshot = apps
        await withTaskGroup(of: Void.self) { group in
            for app in snapshot { group.addTask { await self.refresh(app) } }
        }
        lastRefreshed = Date()
    }

    /// Asks the Hub which apps it knows and adds the ones this catalog lacks, so a new app shows up with no setup here.
    @discardableResult
    public func discoverHubApps() async -> Int {
        guard let hub = hub() else { hubMessage = "This build has no update server set."; return 0 }
        do {
            let found = try await hub.apps()
            var added = 0
            for item in found where !apps.contains(where: { $0.id == item.id || $0.bundleID == item.bundleId }) {
                apps.append(AppDefinition(id: item.id, name: item.name, bundleID: item.bundleId, sourceID: BuiltIn.hubSourceID))
                added += 1
            }
            hubMessage = nil
            if added > 0 { persist() }
            return added
        } catch {
            hubMessage = error.localizedDescription
            return 0
        }
    }

    // MARK: What is installed

    /// The Launcher handed this build to iOS. (It can't see whether the person tapped Install.)
    public func recordInstall(_ app: AppDefinition, release: Release, teamID: String?) {
        installed[app.id] = InstalledRecord(version: release.version, build: release.build, installedAt: Date(), via: .launcher, teamID: teamID)
        skipped[app.id] = nil
        persist()
    }

    /// The person says which version is on the device (installed some other way, or the record is wrong).
    public func markInstalled(_ app: AppDefinition, version: String, build: String) {
        installed[app.id] = InstalledRecord(version: version, build: build, installedAt: Date(), via: .manual, teamID: installed[app.id]?.teamID)
        persist()
    }

    public func forgetInstalled(_ app: AppDefinition) {
        installed[app.id] = nil
        persist()
    }

    // MARK: Skipping and holding

    public func skip(_ app: AppDefinition, release: Release) { skipped[app.id] = release.build; persist() }
    public func stopSkipping(_ app: AppDefinition) { skipped[app.id] = nil; persist() }
    public func isSkipped(_ app: AppDefinition) -> Bool {
        guard let latest = status(for: app).latest else { return false }
        return skipped[app.id] == latest.build
    }

    /// Pins the app: no update is offered until the hold is lifted (for staying on a version that works).
    public func hold(_ app: AppDefinition, at release: Release) { held[app.id] = release.build; persist() }
    public func releaseHold(_ app: AppDefinition) { held[app.id] = nil; persist() }

    // MARK: Editing the catalog

    public func addApp(_ app: AppDefinition) {
        guard !apps.contains(where: { $0.id == app.id }) else { return }
        apps.append(app)
        persist()
    }

    public func updateApp(_ app: AppDefinition) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        var updated = app
        if apps[index].isBuiltIn { updated.isBuiltIn = true }
        apps[index] = updated
        persist()
    }

    public func removeApp(id: String) {
        guard let app = app(id: id), !app.isBuiltIn else { return }
        apps.removeAll { $0.id == id }
        status[id] = nil; installed[id] = nil; skipped[id] = nil; held[id] = nil
        persist()
    }

    public func addSource(_ source: UpdateSource) {
        if let index = sources.firstIndex(where: { $0.id == source.id }) { sources[index] = source } else { sources.append(source) }
        persist()
    }

    public func removeSource(id: String) {
        guard !builtInSources.contains(where: { $0.id == id }), !apps.contains(where: { $0.sourceID == id }) else { return }
        sources.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        file?.save(Persisted(
            apps: apps, sources: sources.filter { source in !builtInSources.contains { $0.id == source.id } },
            installed: installed, skipped: skipped, held: held
        ))
    }
}
