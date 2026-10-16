// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Testing
import Foundation
@testable import LauncherCore

/// Answers requests from a table instead of the network.
final class StubTransport: Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: (Int, Data)] = [:]
    private(set) var requested: [String] = []

    func set(_ path: String, status: Int = 200, json: Any) {
        lock.withLock { routes[path] = (status, (try? JSONSerialization.data(withJSONObject: json)) ?? Data()) }
    }
    func set(_ path: String, status: Int = 200, data: Data) { lock.withLock { routes[path] = (status, data) } }

    private func answer(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        let url = request.url!
        let key = url.host.map { _ in url.path } ?? url.path
        lock.withLock { requested.append(key) }
        let (status, data) = lock.withLock { routes[key] } ?? (404, Data("{}".utf8))
        return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { answer(request) }

    func download(_ request: URLRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> (URL, HTTPURLResponse) {
        let (data, response) = answer(request)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: file)
        progress(1)
        return (file, response)
    }

    func upload(_ request: URLRequest, fromFile file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = answer(request)
        progress(1)
        return (data, response)
    }
}

@MainActor
func makeSettings() -> LauncherSettings {
    let defaults = UserDefaults(suiteName: "launcher-tests-\(UUID().uuidString)")!
    let settings = LauncherSettings(defaults: defaults)
    settings.hubURLString = "https://hub.test:9445"
    return settings
}

@Suite("Release decoding")
struct ReleaseDecodingTests {
    @Test func aBuildNumberMayBeTextOrANumber() throws {
        let text = try JSONDecoder().decode(Release.self, from: Data(#"{"version":"1.0","build":"23","file":"A-1.0-23.ipa"}"#.utf8))
        let number = try JSONDecoder().decode(Release.self, from: Data(#"{"version":"1.0","build":23,"file":"A-1.0-23.ipa"}"#.utf8))
        #expect(text.build == "23" && number.build == "23" && number.buildNumber == 23)
    }

    @Test func latestJSONAndVersionsJSONBothCarryTheirNotes() throws {
        let latest = try JSONDecoder().decode(Release.self, from: Data(#"{"version":"1","build":"1","file":"a.ipa","notes":"From latest"}"#.utf8))
        let entry = try JSONDecoder().decode(Release.self, from: Data(#"{"version":"1","build":"1","file":"a.ipa","summary":"S","added":["a"],"changed":["c"],"fixed":["f"]}"#.utf8))
        #expect(latest.summary == "From latest")
        #expect(entry.summary == "S" && entry.added == ["a"] && entry.changed == ["c"] && entry.fixed == ["f"] && entry.hasNotes)
    }

    @Test func datesWithAndWithoutFractionalSecondsAreBothRead() throws {
        let a = try JSONDecoder().decode(Release.self, from: Data(#"{"version":"1","build":"1","file":"a.ipa","publishedAt":"2026-09-29T11:46:37.000Z"}"#.utf8))
        let b = try JSONDecoder().decode(Release.self, from: Data(#"{"version":"1","build":"1","file":"a.ipa","publishedAt":"2026-09-29T11:46:37Z"}"#.utf8))
        #expect(a.publishedAt != nil && a.publishedAt == b.publishedAt)
    }

    @Test func theReleaseSignatureIsReadAndKept() throws {
        let release = try JSONDecoder().decode(Release.self, from: Data(#"{"version":"1","build":"1","file":"a.ipa","sha256":"ab","signature":"c2ln"}"#.utf8))
        #expect(release.signature == "c2ln")
        let again = try JSONDecoder().decode(Release.self, from: JSONEncoder().encode(release))
        #expect(again.signature == "c2ln")
        let none = try JSONDecoder().decode(Release.self, from: Data(#"{"version":"1","build":"1","file":"a.ipa","signature":7}"#.utf8))
        #expect(none.signature == nil)
    }

    @Test func oneOddFieldNeverHidesTheRelease() throws {
        let release = try JSONDecoder().decode(Release.self, from: Data(#"{"version":"1","build":"1","file":"a.ipa","size":"big","signed":"yes","added":"x","publishedAt":5}"#.utf8))
        #expect(release.file == "a.ipa" && release.size == nil && release.isSigned == nil && release.added.isEmpty && release.publishedAt == nil)
    }
}

@Suite("Versions")
struct AppVersionTests {
    @Test func versionsCompareNumerically() {
        #expect(AppVersion.compare("1.0.10", "1.0.9") == .orderedDescending)
        #expect(AppVersion.compare("1.0", "1.0.0") == .orderedSame)
        #expect(AppVersion.compare("0.9.1", "0.11.0") == .orderedAscending)
    }

    @Test func theBuildNumberBreaksATie() {
        #expect(AppVersion.isNewer(version: "5.1", build: "23", than: "5.1", installedBuild: "22"))
        #expect(!AppVersion.isNewer(version: "5.1", build: "22", than: "5.1", installedBuild: "22"))
        #expect(!AppVersion.isNewer(version: "5.0", build: "99", than: "5.1", installedBuild: "1"))
    }
}

/// Stand-ins for the apps and servers a build might come with.
enum TestApps {
    static let sources = [
        UpdateSource(id: "alpha", name: "Alpha server", baseURL: URL(string: "https://updates.example.test:3000/updates")!),
        UpdateSource(id: "beta", name: "Beta server", baseURL: URL(string: "https://updates.example.test:4021/updates")!),
        UpdateSource(id: "gamma", name: "Gamma server", baseURL: URL(string: "https://updates.example.test:9444/updates")!),
    ]
    static let apps = [
        AppDefinition(id: "alpha", name: "Alpha", bundleID: "com.example.alpha", sourceID: "alpha", symbol: "house.fill", tintHex: "#34C759",
                      signing: AppSigningSettings(appGroupInfoKeys: ["AlphaAppGroup"]), isBuiltIn: true),
        AppDefinition(id: "beta", name: "Beta", bundleID: "com.example.beta", sourceID: "beta", symbol: "cube.transparent", tintHex: "#20C5B5", isBuiltIn: true),
        AppDefinition(id: "gamma", name: "Gamma", bundleID: "com.example.gamma", sourceID: "gamma", symbol: "location.north.line.fill", tintHex: "#FF9F0A",
                      signing: AppSigningSettings(appGroupInfoKeys: ["GammaAppGroup"]), isBuiltIn: true),
    ]
}

@Suite("Catalog")
@MainActor
struct CatalogTests {
    func catalog(_ transport: StubTransport, selfBuild: (String, String)? = ("1.0", "5")) -> CatalogStore {
        CatalogStore(settings: makeSettings(), transport: transport, stateURL: nil, selfBuild: selfBuild, builtInApps: TestApps.apps, builtInSources: TestApps.sources)
    }

    func stubAlpha(_ t: StubTransport, builds: [(String, Int)] = [("1.3.38", 64), ("1.3.37", 63), ("1.3.36", 62)]) {
        t.set("/updates/latest.json", json: ["version": builds[0].0, "build": String(builds[0].1), "file": "Alpha-\(builds[0].0)-\(builds[0].1).ipa", "bundleId": "com.example.alpha"])
        t.set("/updates/versions.json", json: builds.map { ["version": $0.0, "build": String($0.1), "file": "Alpha-\($0.0)-\($0.1).ipa", "summary": "s\($0.1)"] })
    }

    @Test func itKnowsTheBuiltInApps() {
        let store = catalog(StubTransport())
        #expect(store.apps.map(\.id) == ["alpha", "beta", "gamma", "launcher"])
        #expect(store.app(id: "gamma")?.bundleID == "com.example.gamma")
        #expect(store.app(id: "gamma")?.signing.appGroupInfoKeys == ["GammaAppGroup"])
        #expect(store.sources.map(\.id) == ["alpha", "beta", "gamma"])
    }

    @Test func refreshingFillsLatestAndTheWholeHistory() async throws {
        let t = StubTransport(); stubAlpha(t)
        let store = catalog(t)
        let app = try #require(store.app(id: "alpha"))
        await store.refresh(app)
        let status = store.status(for: app)
        #expect(status.phase == .loaded && status.latest?.build == "64" && status.releases.map(\.build) == ["64", "63", "62"])
        #expect(status.latest?.url?.absoluteString == "https://updates.example.test:3000/updates/files/Alpha-1.3.38-64.ipa")
    }

    @Test func aFailureIsKeptWithThatAppAndStopsNothingElse() async throws {
        let t = StubTransport(); stubAlpha(t)
        t.set("/updates/latest.json", status: 500, json: ["error": "boom"])
        let store = catalog(t)
        await store.refreshAll()
        let app = try #require(store.app(id: "alpha"))
        if case .failed(let message) = store.status(for: app).phase { #expect(message == "boom") } else { Issue.record("expected a failure") }
    }

    @Test func noUpdateIsOfferedUntilTheInstalledVersionIsKnown() async throws {
        let t = StubTransport(); stubAlpha(t)
        let store = catalog(t)
        let app = try #require(store.app(id: "alpha"))
        await store.refresh(app)
        #expect(store.availableUpdate(for: app) == nil, "nothing recorded as installed yet")
        store.markInstalled(app, version: "1.3.36", build: "62")
        #expect(store.availableUpdate(for: app)?.build == "64")
        #expect(store.updateCount == 1)
        store.markInstalled(app, version: "1.3.38", build: "64")
        #expect(store.availableUpdate(for: app) == nil && store.updateCount == 0)
    }

    @Test func skippingHidesOnlyThatBuildAndHoldingHidesEverything() async throws {
        let t = StubTransport(); stubAlpha(t)
        let store = catalog(t)
        let app = try #require(store.app(id: "alpha"))
        await store.refresh(app)
        store.markInstalled(app, version: "1.3.36", build: "62")
        let latest = try #require(store.status(for: app).latest)

        store.skip(app, release: latest)
        #expect(store.availableUpdate(for: app) == nil && store.isSkipped(app))
        #expect(store.newestIfNewer(for: app)?.build == "64", "the person can still update by hand")

        store.stopSkipping(app)
        store.hold(app, at: latest)
        #expect(store.availableUpdate(for: app) == nil)
        store.releaseHold(app)
        #expect(store.availableUpdate(for: app)?.build == "64")
    }

    @Test func aLaterBuildIsAnnouncedEvenAfterSkippingAnEarlierOne() async throws {
        let t = StubTransport(); stubAlpha(t)
        let store = catalog(t)
        let app = try #require(store.app(id: "alpha"))
        await store.refresh(app)
        store.markInstalled(app, version: "1.3.36", build: "62")
        store.skip(app, release: try #require(store.status(for: app).latest))
        stubAlpha(t, builds: [("1.3.39", 65), ("1.3.38", 64)])
        await store.refresh(app)
        #expect(store.availableUpdate(for: app)?.build == "65")
    }

    @Test func downgradesAreRecognisedAndChangesListWhatAnUpdateBrings() async throws {
        let t = StubTransport(); stubAlpha(t)
        let store = catalog(t)
        let app = try #require(store.app(id: "alpha"))
        await store.refresh(app)
        store.markInstalled(app, version: "1.3.37", build: "63")
        let releases = store.status(for: app).releases
        #expect(store.isDowngrade(releases[2], for: app) && !store.isDowngrade(releases[0], for: app) && !store.isDowngrade(releases[1], for: app))
        #expect(store.isInstalled(releases[1], for: app) && !store.isInstalled(releases[0], for: app))
        #expect(store.changes(for: app).map(\.build) == ["64"])
    }

    @Test func theLauncherKnowsItsOwnVersion() async throws {
        let t = StubTransport()
        t.set("/updates/launcher/latest.json", json: ["version": "1.1", "build": "6", "file": "L-1.1-6.ipa"])
        t.set("/updates/launcher/versions.json", json: [["version": "1.1", "build": "6", "file": "L-1.1-6.ipa"]])
        let store = catalog(t, selfBuild: ("1.0", "5"))
        let app = try #require(store.app(id: "launcher"))
        await store.refresh(app)
        #expect(store.installedRecord(for: app)?.version == "1.0")
        #expect(store.availableUpdate(for: app)?.build == "6")
        #expect(t.requested.contains("/updates/launcher/latest.json"), "the Launcher's builds come from the Hub")
    }

    @Test func newAppsOnTheHubAppearByThemselves() async throws {
        let t = StubTransport()
        t.set("/apps.json", json: [["id": "newthing", "name": "New Thing", "bundleId": "com.example.newthing"],
                                   ["id": "launcher", "name": "Porthole", "bundleId": "com.example.launcher"]])
        let store = catalog(t)
        #expect(await store.discoverHubApps() == 1)
        let added = try #require(store.app(id: "newthing"))
        #expect(added.sourceID == BuiltIn.hubSourceID && added.name == "New Thing" && !added.isBuiltIn)
        #expect(await store.discoverHubApps() == 0, "asking again adds nothing")
    }

    @Test func builtInAppsCannotBeRemovedButAddedOnesCan() {
        let store = catalog(StubTransport())
        store.removeApp(id: "alpha")
        #expect(store.app(id: "alpha") != nil)
        store.addApp(AppDefinition(id: "mine", name: "Mine", bundleID: "com.me.mine", sourceID: "alpha"))
        store.removeApp(id: "mine")
        #expect(store.app(id: "mine") == nil)
    }

    @Test func whatThePersonChangedIsRemembered() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = CatalogStore(settings: makeSettings(), transport: StubTransport(), stateURL: url, builtInApps: TestApps.apps, builtInSources: TestApps.sources)
        var hc = try #require(first.app(id: "alpha"))
        hc.signing.stripExtensions = true
        first.updateApp(hc)
        first.markInstalled(hc, version: "1.3.0", build: "50")
        first.addApp(AppDefinition(id: "mine", name: "Mine", bundleID: "com.me.mine", sourceID: "beta"))

        let second = CatalogStore(settings: makeSettings(), transport: StubTransport(), stateURL: url, builtInApps: TestApps.apps, builtInSources: TestApps.sources)
        #expect(second.app(id: "alpha")?.signing.stripExtensions == true)
        #expect(second.installedRecord(for: try #require(second.app(id: "alpha")))?.build == "50")
        #expect(second.app(id: "mine")?.name == "Mine")
        #expect(second.app(id: "alpha")?.sourceID == "alpha", "built-in addresses come from the code, not the file")
    }
}

@Suite("Credential vault")
@MainActor
struct VaultTests {
    static func vault(store: any SecretStore = MemorySecretStore()) throws -> CredentialVault {
        let vault = CredentialVault(store: store)
        try vault.importCertificate(SigningFixtures.p12, password: SigningFixtures.password)
        return vault
    }

    @Test func aWrongPasswordIsRefusedAndNothingIsKept() {
        let vault = CredentialVault(store: MemorySecretStore())
        #expect(throws: SigningError.wrongPassword) { try vault.importCertificate(SigningFixtures.p12, password: "nope") }
        #expect(vault.certificates.isEmpty)
    }

    @Test func importingTheSameCertificateTwiceKeepsOneCopy() throws {
        let vault = try Self.vault()
        try vault.importCertificate(SigningFixtures.p12, password: SigningFixtures.password, label: "Renamed")
        #expect(vault.certificates.count == 1 && vault.certificates[0].label == "Renamed")
    }

    @Test func whatWasImportedSurvivesARestart() throws {
        let store = MemorySecretStore()
        let vault = try Self.vault(store: store)
        try vault.importProfile(TestIPA.profileData(appID: "TEAM123456.com.example.app", name: "App"))
        let again = CredentialVault(store: store)
        #expect(again.certificates.count == 1 && again.profiles.count == 1 && again.canSign)
    }

    @Test func noCertificateAndNoProfileEachSayWhatToDo() throws {
        let empty = CredentialVault(store: MemorySecretStore())
        if case .failure(let error) = empty.selection(for: "com.a.b") { #expect(error.localizedDescription.contains("certificate")) } else { Issue.record("expected failure") }
        let certOnly = try Self.vault()
        if case .failure(let error) = certOnly.selection(for: "com.a.b") { #expect(error.localizedDescription.contains("profile")) } else { Issue.record("expected failure") }
    }

    @Test func theProfileThatNamesTheAppIsPreferred() throws {
        let vault = try Self.vault()
        try vault.importProfile(TestIPA.profileData(appID: "TEAM123456.*", name: "Wild"))
        try vault.importProfile(TestIPA.profileData(appID: "TEAM123456.com.example.app", name: "Exact"))
        let selection = try vault.selection(for: "com.example.app").get()
        #expect(selection.matcher.best(for: "com.example.app")?.explicitBundleID == "com.example.app")
    }

    @Test func removingThingsWorks() throws {
        let vault = try Self.vault()
        let profile = try vault.importProfile(TestIPA.profileData(appID: "TEAM123456.*", name: "Wild"))
        vault.removeProfile(id: profile.id)
        vault.removeCertificate(id: vault.certificates[0].id)
        #expect(vault.isEmpty)
    }

    @Test func problemsAreListedWorstFirst() throws {
        let vault = CredentialVault(store: MemorySecretStore())
        #expect(vault.problems().map(\.severity) == [.blocking, .blocking])
        try vault.importCertificate(SigningFixtures.p12, password: SigningFixtures.password)
        #expect(vault.problems().contains { $0.subject == "Profile" })
    }
}
