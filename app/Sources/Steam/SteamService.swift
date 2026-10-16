// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import LauncherCore

/// What went wrong, in words for the person.
struct SteamFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// The signed-in Steam account and the one connection to Steam's servers, as the rest of the app uses them. Everything runs on the main actor, which is
/// where the protocol code expects to be called.
@MainActor
final class SteamService {
    static let shared = SteamService()

    private let api = SteamAPI(transport: URLSessionSteamTransport())
    private let account: SteamAccount
    private var backend: SteamCMBackend?
    /// While Valve's own client is signed in for a Dock launch this connection must stay closed: one sign-in of the account at a time.
    private var suspended = false

    init() {
        // The Steam code reports into the app's log (from any thread).
        SteamLog.sink = { text in DispatchQueue.main.async { LogStore.shared.log(text) } }
        account = SteamAccount(api: api, store: KeychainSteamSessionStore(service: BuildIdentity.keychainService + ".steam"))
    }

    // MARK: Who is signed in

    var isSignedIn: Bool { account.isSignedIn }
    var accountName: String? { account.displayName }
    func makeAuthenticator() -> SteamAuthenticator { SteamAuthenticator(api: api) }

    /// Keeps a finished sign-in.
    func adopt(_ session: SteamAccountSession) {
        closeConnection()
        account.adopt(session)
        suspended = false
        NotificationCenter.default.post(name: SteamSignIn.didChange, object: nil)
    }

    func signOut() {
        closeConnection()
        account.signOut()
        NotificationCenter.default.post(name: SteamSignIn.didChange, object: nil)
    }

    /// What Valve's client needs to sign in the same account for a Dock launch.
    func credentialsForDock() -> (accountName: String, refreshToken: String)? {
        guard let session = account.session, !session.refreshToken.isEmpty else { return nil }
        return (session.accountName, session.refreshToken)
    }

    // MARK: The connection

    private func connection() throws -> SteamCMBackend {
        guard !suspended else { throw SteamFailure(message: "Steam is being used by the game right now. Try again when it has closed.") }
        if let backend { return backend }
        guard let session = account.session, !session.refreshToken.isEmpty else { throw SteamFailure(message: "Sign in to Steam first.") }
        let made = SteamCMBackend(logOn: .account(name: session.accountName, refreshToken: session.refreshToken, steamID: session.steamID))
        backend = made
        return made
    }

    private func closeConnection() { backend?.close(); backend = nil }

    /// Steam no longer accepts the saved sign-in (the password changed, the session was revoked): sign out so the person signs in again.
    private func checkSessionOver(_ error: Error) {
        let text = (error as? SteamContentError)?.message ?? ""
        if text.contains("Sign in for downloads again") || text.contains("sign-in for downloads has expired") { signOut() }
    }

    /// Games and downloads leave Steam's servers alone while a Dock launch has Valve's client signed in.
    func suspend() async { suspended = true; closeConnection() }
    func resume() { suspended = false }
    func logoff() { closeConnection() }

    // MARK: Library

    func ownedApps() async throws -> [SteamAppInfo] {
        let backend = try connection()
        do {
            return try await withCheckedThrowingContinuation { continuation in
                backend.ownedApps { continuation.resume(with: $0.mapError { $0 as Error }) }
            }
        } catch { checkSessionOver(error); throw error }
    }

    func appInfo(_ appID: Int) async throws -> SteamAppInfo {
        let backend = try connection()
        return try await withCheckedThrowingContinuation { continuation in
            backend.appInfo(appID) { continuation.resume(with: $0.mapError { $0 as Error }) }
        }
    }

    // MARK: Steam Cloud (download only)

    /// Before a game is started through Steam: brings this account's cloud files for it onto the device (see SteamCloud.swift). Reads from Steam only.
    func cloudDownload(appID: Int, driveC: URL, installFolder: URL?, progress: ((Int, Int, String) -> Void)? = nil) async throws -> SteamCloudReport {
        let backend = try connection()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            backend.start { continuation.resume(with: $0.mapError { $0 as Error }) }
        }
        return try await SteamCloudSync.downloadMissing(appID: appID, transport: SteamCMCloudTransport(cm: backend.cm), driveC: driveC, installFolder: installFolder, progress: progress)
    }

    // MARK: Downloads

    /// Downloads and records one game. Cancelling the task stops the transfer and keeps what is done, so the next try continues.
    func install(appID: Int, name: String, steamApps: URL, progress: @escaping @MainActor (SteamDownloadProgress) -> Void) async throws -> (folder: URL, info: SteamAppInfo) {
        let backend = try connection()
        let installer = SteamInstaller(appid: appID, name: name, steamApps: steamApps, backend: backend)
        installer.ownerSteamID = account.session?.steamID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, SteamAppInfo), Error>) in
                var finished = false
                func finish(_ result: Result<(URL, SteamAppInfo), Error>) {
                    guard !finished else { return }
                    finished = true
                    installer.onState = nil
                    continuation.resume(with: result)
                }
                installer.onState = { state in
                    switch state {
                    case .idle: break
                    case .preparing: progress(SteamDownloadProgress())
                    case .downloading(let p): progress(p)
                    case .finished:
                        if let info = installer.installInfo { finish(.success((installer.gameFolder, info))) }
                        else { finish(.failure(SteamFailure(message: "The download finished but Steam's information about the game was lost."))) }
                    case .failed(let message): finish(.failure(SteamFailure(message: message)))
                    case .cancelled: finish(.failure(CancellationError()))
                    }
                }
                if Task.isCancelled { finish(.failure(CancellationError())); return }
                installer.start()
            }
        } onCancel: {
            Task { @MainActor in installer.cancel() }
        }
    }
}
