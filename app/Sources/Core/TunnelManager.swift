// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import NetworkExtension
import Observation

/// Our own loopback tunnel (see Tunnel/PacketTunnelProvider.swift): lets the JIT helper reach the device's debug service without LocalDevVPN.
/// iOS allows one VPN at a time, so this replaces any other active VPN (LocalDevVPN, Tailscale) while it is on.
@MainActor
@Observable
final class TunnelManager {
    static let shared = TunnelManager()

    private(set) var status: NEVPNStatus = .invalid
    var message: String?

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    var isConnected: Bool { status == .connected }

    var statusText: String {
        switch status {
        case .connected: "connected"
        case .connecting: "connecting"
        case .reasserting: "reconnecting"
        case .disconnecting: "disconnecting"
        case .disconnected: "off"
        case .invalid: "not set up"
        @unknown default: "unknown"
        }
    }

    /// The id of the embedded tunnel extension AS INSTALLED (a signing service may have rewritten it).
    private var providerBundleID: String? {
        Bundle.main.builtInPlugInsURL.flatMap { Bundle(url: $0.appendingPathComponent("F4Tunnel.appex")) }?.bundleIdentifier
    }

    /// Finds our VPN configuration, or creates it. The first save makes iOS ask the person to allow it.
    private func load() async throws -> NETunnelProviderManager {
        // Always read the configuration afresh: iOS disables a VPN configuration whenever another VPN is switched on (NEVPNError 2, "configuration
        // disabled"), so a cached copy can be stale. A disabled one is enabled and saved again below.
        guard let providerID = providerBundleID else { throw TunnelError.missingExtension }
        let all = try await NETunnelProviderManager.loadAllFromPreferences()
        let found = all.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerID }
        let manager = found ?? NETunnelProviderManager()
        if found == nil || manager.isEnabled == false {
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = providerID
            proto.serverAddress = "10.7.0.1"          // shown in Settings; the tunnel itself is local
            manager.protocolConfiguration = proto
            manager.localizedDescription = Self.configurationName
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
        }
        self.manager = manager
        status = manager.connection.status
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: manager.connection, queue: .main) { [weak self] _ in
            Task { @MainActor in
                let now = self?.manager?.connection.status ?? .invalid
                if now != self?.status { LogStore.shared.log("[tunnel] status -> \(TunnelDiagnostics.name(now))") }
                self?.status = now
            }
        }
        return manager
    }

    private var inFlight: Task<Void, Error>?

    /// Turns the tunnel on and waits until it is connected. One attempt at a time: asking again while one is running waits for that one (several at
    /// once fight over the same VPN configuration).
    ///
    /// The very first start after the app is installed or UPDATED is the fragile one: iOS may hold a stale configuration, or a record of the old copy
    /// of the tunnel extension, and then `startVPNTunnel` is accepted but the tunnel never leaves "disconnected". Deleting the app clears that, which is
    /// why a reinstall used to be the only cure. So after two failed tries the app deletes its own VPN configuration and makes a fresh one (iOS asks the
    /// person to allow the VPN again), which does the same without touching any game.
    /// Settings > JIT and tunnel > "Use LocalDevVPN instead": another app's VPN (LocalDevVPN uses the same 10.7.0.x addresses) provides the tunnel, so this app
    /// does not start its own, which replaces any other VPN and sometimes fails to come up.
    static let useLocalDevVPNKey = "f4.useLocalDevVPN"
    static var useLocalDevVPN: Bool { UserDefaults.standard.bool(forKey: useLocalDevVPNKey) }

    func connect(timeout: TimeInterval = 25) async throws {
        if !InstallCheck.hasTunnel {
            LogStore.shared.log("[tunnel] this install has no tunnel extension: LocalDevVPN (or another tool's link) has to provide the private link")
            return
        }
        if Self.useLocalDevVPN {
            LogStore.shared.log("[tunnel] \"Use LocalDevVPN instead\" is on: this app's own tunnel is not started (LocalDevVPN has to be on)")
            return
        }
        if let running = inFlight { return try await running.value }
        let task = Task { @MainActor in try await self.connectWithRetries(timeout: timeout) }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }

    private func connectWithRetries(timeout: TimeInterval) async throws {
        message = nil
        var lastError: Error = TunnelError.notConnected(.invalid)
        for attempt in 1...3 {
            if attempt == 3 {
                LogStore.shared.log("[tunnel] still not up after two tries: deleting this app's VPN configuration and making a fresh one", level: .error)
                await resetConfiguration()
            }
            do {
                try await connectOnce(timeout: timeout, attempt: attempt)
                return
            } catch let error as TunnelError {
                if case .missingExtension = error { throw error }
                lastError = error
            } catch {
                lastError = error
            }
            LogStore.shared.log("[tunnel] attempt \(attempt) failed: \(lastError.localizedDescription)", level: .error)
            if attempt < 3 { try? await Task.sleep(for: .seconds(2)) }
        }
        // Never came up: say why, as far as iOS and the app's own signing can tell.
        if let manager, let reason = await TunnelDiagnostics.lastDisconnectReason(manager.connection) {
            LogStore.shared.log("[tunnel] iOS reports: \(reason)", level: .error)
        } else {
            LogStore.shared.log("[tunnel] iOS reported no error (the tunnel extension may not have started at all)", level: .error)
        }
        for line in TunnelDiagnostics.signingReport() { LogStore.shared.log("[tunnel] \(line)", level: line.hasPrefix("PROBLEM") ? .error : .info) }
        throw lastError
    }

    /// Deletes every VPN configuration this app made (including ones left by an older copy of the app) and forgets the cached one. The next `connect`
    /// makes a new configuration, which iOS asks the person to allow. Nothing else in the app is touched.
    func resetConfiguration() async {
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        let providerID = providerBundleID
        let all = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        var removed = 0
        for found in all {
            let ours = (found.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerID || found.localizedDescription == Self.configurationName
            guard ours else { continue }
            found.connection.stopVPNTunnel()
            do { try await found.removeFromPreferences(); removed += 1 } catch { LogStore.shared.log("[tunnel] couldn't delete a configuration: \(error.localizedDescription)", level: .error) }
        }
        manager = nil; status = .invalid
        LogStore.shared.log("[tunnel] deleted \(removed) VPN configuration(s)")
        try? await Task.sleep(for: .milliseconds(500))
    }

    static let configurationName = "Porthole JIT tunnel"

    private func connectOnce(timeout: TimeInterval, attempt: Int) async throws {
        let manager = try await load()
        LogStore.shared.log("[tunnel] attempt \(attempt): status \(manager.connection.status.rawValue), enabled \(manager.isEnabled)")
        if manager.connection.status == .connected { status = .connected; return }
        do { try manager.connection.startVPNTunnel() }
        catch let error as NSError where error.domain == NEVPNErrorDomain
            && (error.code == NEVPNError.configurationDisabled.rawValue || error.code == NEVPNError.configurationStale.rawValue
                || error.code == NEVPNError.configurationInvalid.rawValue) {
            // Another VPN was switched on, or the app was just updated and iOS still holds the old configuration: write ours again and retry once.
            LogStore.shared.log("[tunnel] start refused (\(error.code)); saving the configuration again")
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            try manager.connection.startVPNTunnel()
        }
        let started = Date()
        var restarted = false
        var sawConnecting = false
        while Date().timeIntervalSince(started) < timeout {
            status = manager.connection.status
            if status == .connected { LogStore.shared.log("[tunnel] up after \(String(format: "%.1f", Date().timeIntervalSince(started))) s"); return }
            if status == .connecting || status == .reasserting { sawConnecting = true }
            // "Connecting" and straight back to "disconnected" within moments means iOS refused to run the tunnel extension at all (a crashing extension takes
            // far longer to die). Waiting out the timeout would only make the person wait: say what iOS reported and fail now so the next step can run.
            if status == .disconnected, sawConnecting, Date().timeIntervalSince(started) < 10 {
                let reason = await TunnelDiagnostics.lastDisconnectReason(manager.connection)
                LogStore.shared.log("[tunnel] iOS ended the tunnel straight after starting it: \(reason ?? "it gave no reason")", level: .error)
                throw TunnelError.refusedAtStart
            }
            // Right after startVPNTunnel the status can read "disconnected" for a while (the first start loads the tunnel extension, and iOS may be
            // showing its allow-VPN prompt). Ask once more after a few seconds; give up on it only near the end.
            if status == .disconnected, !sawConnecting, !restarted, Date().timeIntervalSince(started) > 6 {
                restarted = true
                LogStore.shared.log("[tunnel] still off after 6 s; starting it again")
                try? manager.connection.startVPNTunnel()
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        status = manager.connection.status
        throw TunnelError.notConnected(status)
    }

    func disconnect() {
        guard let manager else { return }
        if manager.connection.status == .connected || manager.connection.status == .connecting || manager.connection.status == .reasserting {
            LogStore.shared.log("[tunnel] turning off")
        }
        manager.connection.stopVPNTunnel()
        VPNGuard.shared.restoreIfPaused()     // brings the person's own VPN back, unless a game is starting or running
    }

    /// At app start: if our tunnel was left on (the app was closed or crashed mid-way), turn it off. Never creates the configuration (that would ask the person to allow a VPN).
    func stopLeftoverTunnel() async {
        guard manager == nil, let providerID = providerBundleID,
              let all = try? await NETunnelProviderManager.loadAllFromPreferences(),
              let found = all.first(where: { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerID }) else { return }
        manager = found
        status = found.connection.status
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: found.connection, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.status = self?.manager?.connection.status ?? .invalid }
        }
        if status == .connected || status == .connecting || status == .reasserting { disconnect() }
    }

    enum TunnelError: LocalizedError {
        case missingExtension
        case notConnected(NEVPNStatus)
        /// iOS started the tunnel and ended it again at once. After an app update this is iOS holding stale information about the tunnel extension, and
        /// restarting the device clears it.
        case refusedAtStart
        var errorDescription: String? {
            switch self {
            case .missingExtension: "The tunnel extension is missing from this build."
            case .refusedAtStart: "iOS wouldn't start the tunnel. After an app update this usually clears by restarting the device. Restart it and try again; your games and settings are not affected."
            case .notConnected: "The tunnel did not connect. Allow the VPN when iOS asks, and check the tunnel extension is signed with a profile that has the Network Extension (packet tunnel) entitlement."
            }
        }
    }
}
