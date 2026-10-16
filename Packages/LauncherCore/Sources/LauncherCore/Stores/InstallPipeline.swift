// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import Observation

/// The whole trip from "Update" to an installed app: download the build, check it arrived intact, sign it on this device with the person's
/// certificate and profiles, and install it on this device. Nothing the person owns leaves the device: the signed copy is never uploaded. When the
/// device cannot install it itself, the signed file is kept so the person can install it with a tool of their own.
///
/// One job at a time; the phase and a running log are observable so the screen can show exactly where it is.
@MainActor
@Observable
public final class InstallPipeline {
    public enum Phase: Equatable, Sendable {
        case downloading(Double)
        case signing(String)
        /// Handing the signed build to iOS's installer on this device (stage name, 0…1).
        case installing(String, Double)
        /// iOS installed it; nothing is left to do.
        case installed
        /// Signed and kept as a file (the device could not install it itself, or Sign ▸ Save): offer it to the share sheet.
        case saved(URL)
        case failed(String)
    }

    public struct Job: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let appID: String
        public let appName: String
        public let title: String
        public let kind: ActivityEntry.Kind
        public var phase: Phase
        public var warnings: [String] = []
        public var log: [String] = []
        public var startedAt = Date()

        public var isFinished: Bool {
            switch phase { case .saved, .installed, .failed: true; default: false }
        }
    }

    public private(set) var job: Job?
    /// Installs on this device directly when set and available.
    public var deviceInstaller: (any DeviceInstaller)?
    /// Looked at before anything is downloaded: returns why a release must not be installed (a signature that is missing or wrong), or nil. The app sets it
    /// when it carries the maintainer's release key, so a changed update server cannot hand it a build the maintainer never made.
    public var releaseCheck: (@Sendable (AppDefinition, Release) -> String?)?

    private let catalog: CatalogStore
    private let vault: CredentialVault
    private let settings: LauncherSettings
    private let activity: ActivityLog
    private let downloads: URL
    private let work: URL
    private var task: Task<Void, Never>?

    public init(catalog: CatalogStore, vault: CredentialVault, settings: LauncherSettings, activity: ActivityLog,
                downloads: URL = FileStorage.cacheURL("Downloads"), work: URL = FileStorage.cacheURL("Signed")) {
        self.catalog = catalog
        self.vault = vault
        self.settings = settings
        self.activity = activity
        self.downloads = downloads
        self.work = work
    }

    public var isBusy: Bool { job.map { !$0.isFinished } ?? false }

    // MARK: Starting

    /// Installs `release` of `app`: a new version, a re-install, or a downgrade.
    public func start(app: AppDefinition, release: Release) {
        guard !isBusy else { return }
        let downgrade = catalog.isDowngrade(release, for: app)
        job = Job(id: UUID(), appID: app.id, appName: app.name, title: "\(app.name) \(release.title)", kind: downgrade ? .downgrade : .install, phase: .downloading(0))
        task = Task { await self.run(app: app, release: release) }
    }

    /// Signs an IPA the person picked from Files (anything, not just their own apps) and offers it for install.
    public func startLocal(ipa: URL, name: String, options: SigningOptions, saveOnly: Bool = false) {
        guard !isBusy else { return }
        job = Job(id: UUID(), appID: "local", appName: name, title: "\(name) (from Files)", kind: .signOnly, phase: .signing("Reading the file…"))
        task = Task { await self.runLocal(ipa: ipa, name: name, options: options, saveOnly: saveOnly) }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        if isBusy { job?.phase = .failed("Cancelled.") }
    }

    /// Clears a finished job from the screen.
    public func dismiss() {
        guard !isBusy else { return }
        job = nil
    }

    // MARK: Running

    private func run(app: AppDefinition, release: Release) async {
        let started = Date()
        var report: [String] = []
        func note(_ text: String) { report.append(text); job?.log.append(text) }
        do {
            // 1. Is there anything to sign with? Fail before downloading 40 MB.
            let selection = try vault.selection(for: app.bundleID, settings: app.signing).get()
            note("certificate: \(vault.certificates.first { $0.id == selection.certificateID }?.label ?? "?")")
            guard let client = catalog.client(for: app) else { throw NetworkError.notConfigured("This app's source isn't set up.") }
            if let refusal = releaseCheck?(app, release) { throw NetworkError.notConfigured(refusal) }
            // 2. Download (a build already on the device is reused when its checksum still matches).
            try Task.checkCancellation()
            job?.phase = .downloading(0)
            let file = try await cachedDownload(release, client: client)
            note("downloaded \(release.file) (\(Self.megabytes(file)))")

            // 3. Sign.
            let signedFile = try await sign(ipaAt: file, selection: selection, options: Self.options(for: app), note: note)

            // 4. Install on this device. When it cannot (no pairing file, the private link is not up...), keep the signed file: it is the person's own
            // copy, signed with their own certificate, and nothing is sent anywhere.
            try Task.checkCancellation()
            let team = selection.profiles.first?.teamID
            var whyNot = "this device can't install it by itself"
            if let installer = deviceInstaller, await installer.isAvailable() {
                do {
                    job?.phase = .installing("Connecting to this device", 0)
                    try await installer.install(ipa: signedFile.url) { stage, fraction in
                        Task { @MainActor in if case .installing = self.job?.phase { self.job?.phase = .installing(stage, fraction) } }
                    }
                    try? FileManager.default.removeItem(at: signedFile.url)
                    note("installed on this device")
                    job?.warnings = signedFile.warnings
                    catalog.recordInstall(app, release: release, teamID: team)
                    job?.phase = .installed
                    activity.add(ActivityEntry(
                        kind: job?.kind ?? .install, appName: app.name, bundleID: app.bundleID, version: release.version, build: release.build,
                        title: "Installed \(app.name) \(release.title)", detail: Self.detail(report, signedFile, seconds: Date().timeIntervalSince(started))
                    ))
                    return
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    whyNot = error.localizedDescription
                    note("on-device install failed: \(whyNot)")
                }
            } else {
                note("on-device install is not available")
            }
            job?.warnings = signedFile.warnings + ["It was signed but not installed: \(whyNot). The signed file is kept so you can install it with your own tool."]
            job?.phase = .saved(signedFile.url)
            activity.add(ActivityEntry(
                kind: job?.kind ?? .install, appName: app.name, bundleID: app.bundleID, version: release.version, build: release.build,
                title: "Signed \(app.name) \(release.title)", detail: Self.detail(report, signedFile, seconds: Date().timeIntervalSince(started))
            ))
        } catch is CancellationError {
            job?.phase = .failed("Cancelled.")
        } catch {
            fail(error, app: app, release: release, report: report)
        }
    }

    private func runLocal(ipa: URL, name: String, options: SigningOptions, saveOnly: Bool) async {
        let started = Date()
        var report: [String] = []
        func note(_ text: String) { report.append(text); job?.log.append(text) }
        do {
            let info = try IPAInspector.inspect(try Data(contentsOf: ipa, options: .mappedIfSafe))
            let bundleID = options.bundleID ?? info.bundleID
            let selection = try vault.selection(for: bundleID).get()
            let signedFile = try await sign(ipaAt: ipa, selection: selection, options: options, note: note)
            job?.warnings = signedFile.warnings
            if saveOnly {
                job?.phase = .saved(signedFile.url)
                activity.add(ActivityEntry(kind: .signOnly, appName: info.name, bundleID: signedFile.bundleID, version: signedFile.version, build: signedFile.build,
                                           title: "Signed \(info.name) for export", detail: Self.detail(report, signedFile, seconds: Date().timeIntervalSince(started))))
                return
            }
            if let installer = deviceInstaller, await installer.isAvailable() {
                do {
                    job?.phase = .installing("Connecting to this device", 0)
                    try await installer.install(ipa: signedFile.url) { stage, fraction in
                        Task { @MainActor in if case .installing = self.job?.phase { self.job?.phase = .installing(stage, fraction) } }
                    }
                    try? FileManager.default.removeItem(at: signedFile.url)
                    job?.phase = .installed
                    activity.add(ActivityEntry(kind: .signOnly, appName: info.name, bundleID: signedFile.bundleID, version: signedFile.version, build: signedFile.build,
                                               title: "Installed \(info.name) from Files", detail: Self.detail(report, signedFile, seconds: Date().timeIntervalSince(started))))
                    return
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    job?.warnings.append("It was signed but not installed: \(error.localizedDescription). The signed file is kept.")
                }
            }
            job?.phase = .saved(signedFile.url)
            activity.add(ActivityEntry(kind: .signOnly, appName: info.name, bundleID: signedFile.bundleID, version: signedFile.version, build: signedFile.build,
                                       title: "Signed \(info.name) from Files", detail: Self.detail(report, signedFile, seconds: Date().timeIntervalSince(started))))
        } catch is CancellationError {
            job?.phase = .failed("Cancelled.")
        } catch {
            job?.phase = .failed(error.localizedDescription)
            activity.add(ActivityEntry(kind: .failure, appName: name, title: "Couldn't sign \(name)", detail: (report + [error.localizedDescription]).joined(separator: "\n"), succeeded: false))
        }
    }

    /// What signing produced, written to a file ready to install.
    struct SignedFile {
        let url: URL
        let bundleID: String
        let version: String
        let build: String
        let bundles: [IPASigner.SignedBundle]
        let warnings: [String]
    }

    private func sign(ipaAt file: URL, selection: SigningSelection, options: SigningOptions, note: (String) -> Void) async throws -> SignedFile {
        job?.phase = .signing("Checking the certificate chain…")
        var identity = selection.identity
        await identity.completeChain()
        let profiles = selection.profiles
        job?.phase = .signing("Signing…")
        let jobID = job?.id
        let result = try await Task.detached(priority: .userInitiated) {
            let input = try Data(contentsOf: file, options: .mappedIfSafe)
            return try IPASigner.sign(ipa: input, identity: identity, profiles: profiles, options: options) { step in
                Task { @MainActor in
                    if self.job?.id == jobID, case .signing = self.job?.phase { self.job?.phase = .signing(step) }
                }
            }
        }.value
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let output = work.appendingPathComponent("\(result.bundleID)-\(result.version)-\(result.build)-signed.ipa")
        try result.ipa.write(to: output, options: .atomic)
        note("signed \(result.bundles.count) bundle(s) → \(Self.megabytes(output))")
        for warning in result.warnings { note("warning: \(warning)") }
        return SignedFile(url: output, bundleID: result.bundleID, version: result.version, build: result.build, bundles: result.bundles, warnings: result.warnings)
    }

    private func cachedDownload(_ release: Release, client: UpdatesClient) async throws -> URL {
        let existing = downloads.appendingPathComponent(UpdatesClient.safeName(release.file))
        if FileManager.default.fileExists(atPath: existing.path), let wanted = release.sha256?.lowercased(), !wanted.isEmpty,
           (try? UpdatesClient.sha256(of: existing)) == wanted {
            job?.phase = .downloading(1)
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: existing.path)
            return existing
        }
        let file = try await client.download(release, to: downloads) { fraction in
            Task { @MainActor in if case .downloading = self.job?.phase { self.job?.phase = .downloading(fraction) } }
        }
        pruneDownloads(keeping: settings.keptDownloads)
        return file
    }

    /// Keeps the newest `count` downloads; older ones can always be fetched again.
    func pruneDownloads(keeping count: Int) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(at: downloads, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let ipas = names.filter { $0.pathExtension == "ipa" }.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
            ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for old in ipas.dropFirst(max(1, count)) { try? fm.removeItem(at: old) }
    }

    /// Deletes every downloaded and half-signed file (Settings ▸ Storage).
    public func clearCaches() {
        try? FileManager.default.removeItem(at: downloads)
        try? FileManager.default.removeItem(at: work)
    }

    public func cacheSize() -> Int {
        [downloads, work].reduce(0) { total, directory in
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return total + files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
    }

    // MARK: Helpers

    static func options(for app: AppDefinition) -> SigningOptions {
        SigningOptions(
            bundleID: app.signing.bundleIDOverride, displayName: app.signing.displayNameOverride, stripExtensions: app.signing.stripExtensions,
            stripWatchApps: app.signing.stripWatchApps, enableFileSharing: app.signing.enableFileSharing, appGroupInfoKeys: app.signing.appGroupInfoKeys,
            stripExtensionNames: app.signing.stripExtensionNames ?? []
        )
    }

    private func fail(_ error: Error, app: AppDefinition, release: Release, report: [String]) {
        let message = error.localizedDescription
        job?.phase = .failed(message)
        activity.add(ActivityEntry(
            kind: .failure, appName: app.name, bundleID: app.bundleID, version: release.version, build: release.build,
            title: "Couldn't install \(app.name) \(release.title)", detail: (report + ["error: \(message)"]).joined(separator: "\n"), succeeded: false
        ))
    }

    private static func detail(_ report: [String], _ signed: SignedFile, seconds: TimeInterval) -> String {
        var lines = report
        for bundle in signed.bundles where bundle.kind != .dylib {
            lines.append("  \(bundle.kind.rawValue) \(bundle.path.isEmpty ? "(app)" : bundle.path)  \(bundle.identifier)\(bundle.profileName.map { "  profile “\($0)”" } ?? "")")
        }
        lines.append("took \(String(format: "%.1f", seconds)) s")
        return lines.joined(separator: "\n")
    }

    private static func megabytes(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return String(format: "%.1f MB", Double(size) / 1_048_576)
    }
}
