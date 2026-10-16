// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import UIKit
import CoreImage.CIFilterBuiltins

/// The few things the rest of the app asks about the Steam sign-in.
enum SteamSignIn {
    static let didChange = Notification.Name("PortholeSteamSignInChanged")

    @MainActor static var isSignedIn: Bool { SteamService.shared.isSignedIn }
    @MainActor static var accountName: String? { SteamService.shared.accountName }
    @MainActor static func signOut() { SteamService.shared.signOut() }
    @MainActor static func credentialsForDock() -> (accountName: String, refreshToken: String)? { SteamService.shared.credentialsForDock() }

    /// Madeira's app-side switches (`env.NAME` in madeira.cfg, else the environment, else the default). Anything but "0" means on.
    nonisolated static func flag(_ name: String, default fallback: Bool) -> Bool { MadeiraConfig.flag(name, fallback: fallback) }

    /// A sentence for the person.
    static func message(_ error: Error) -> String {
        if let error = error as? SteamFailure { return error.message }
        if let error = error as? SteamContentError { return error.message }
        if let error = error as? SteamAPIError { return error.description }
        if let error = error as? SteamCM.ConnectionError { return error.description }
        if let error = error as? URLError {
            return error.code == .notConnectedToInternet || error.code == .networkConnectionLost ? "No internet connection." : "Couldn't reach Steam (\(error.localizedDescription))."
        }
        return error.localizedDescription
    }

    /// A short label for the log: what kind of failure, never an account name, password or token.
    static func reason(_ error: Error) -> String {
        if let error = error as? SteamAPIError { return "api eresult=\(error.eresult.map(String.init) ?? "-") http=\(error.http.map(String.init) ?? "-")" }
        if error is SteamContentError { return "content" }
        if let error = error as? SteamCM.ConnectionError {
            if case .logOnRefused(let code) = error { return "logon-refused \(code)" }
            return "connection"
        }
        if let error = error as? URLError { return "network \(error.code.rawValue)" }
        if error is SteamFailure { return "failed" }
        return String(describing: type(of: error))
    }
}

/// What the sign-in screen shows while a sign-in is under way.
@MainActor
final class SteamSignInModel: ObservableObject {
    static let shared = SteamSignInModel()

    struct GuardPrompt: Equatable {
        /// A code can be typed now (from the Steam app, or from an email); nil when the only way is to approve on the phone.
        var codeType: SteamAuthenticator.CodeKind?
        var hint = ""
        var canApprove = false
    }

    @Published private(set) var signInBusy = false
    @Published private(set) var signInError: String?
    @Published private(set) var guardPrompt: GuardPrompt?
    @Published private(set) var qrImage: UIImage?

    private var authenticator: SteamAuthenticator?

    func signIn(account: String, password: String) {
        start { $0.startCredentials(account: account.trimmingCharacters(in: .whitespaces), password: password) }
    }

    func beginQR() { start { $0.startQR() } }

    func submitGuardCode(_ code: String) {
        guard let type = guardPrompt?.codeType else { return }
        authenticator?.submitCode(code, kind: type)
    }

    func cancelSignIn() {
        authenticator?.cancel(); authenticator = nil
        signInBusy = false; guardPrompt = nil; qrImage = nil
    }

    private func start(_ begin: (SteamAuthenticator) -> Void) {
        authenticator?.cancel()
        let made = SteamService.shared.makeAuthenticator()
        authenticator = made
        signInBusy = true; signInError = nil; guardPrompt = nil; qrImage = nil
        made.onEvent = { [weak self, weak made] event in
            MainActor.assumeIsolated { if let self, let made, self.authenticator === made { self.handle(event) } }
        }
        begin(made)
    }

    private func handle(_ event: SteamAuthenticator.Event) {
        switch event {
        case .qr(let link): qrImage = Self.qr(link)
        case .approve(let text):
            var prompt = guardPrompt ?? GuardPrompt()
            if text.contains("Approve") || text.contains("approve") { prompt.canApprove = true }
            if prompt.canApprove || prompt.codeType != nil { guardPrompt = prompt }
        case .needsCode(let kind, let text):
            var prompt = guardPrompt ?? GuardPrompt()
            prompt.codeType = kind
            if kind == .email, let range = text.range(of: "sent to ") { prompt.hint = String(text[range.upperBound...]) }
            guardPrompt = prompt
        case .codeRejected(let text): signInError = text
        case .signedIn(let session):
            authenticator = nil; signInBusy = false; guardPrompt = nil; qrImage = nil
            SteamService.shared.adopt(session)
        case .failed(let text):
            authenticator = nil; signInBusy = false; guardPrompt = nil; qrImage = nil; signInError = text
        }
    }

    private static func qr(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}
