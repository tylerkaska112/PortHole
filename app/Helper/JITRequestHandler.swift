// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import StikJIT

/// Runs inside the helper extension. Receives the host's XPC endpoint, then on request attaches a debugserver to the host's PID, runs Madeira's JIT script
/// (bundled in this extension) and detaches when the script is told to. Needs: LocalDevVPN connected, a pairing file, and a host with get-task-allow.
@objc(JITRequestHandler)
final class JITRequestHandler: NSObject, NSExtensionRequestHandling, F4JITWorker {
    private var context: NSExtensionContext?
    private var connection: NSXPCConnection?
    private var host: F4JITHost?
    private var accepted = false
    private let queue = DispatchQueue(label: "site.portholehq.jit.worker")

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let endpoint = item.userInfo?["F4JITEndpoint"] as? NSXPCListenerEndpoint else {
            context.cancelRequest(withError: CocoaError(.coderReadCorrupt)); return
        }
        self.context = context
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.exportedInterface = NSXPCInterface(with: F4JITWorker.self)
        connection.exportedObject = self
        connection.remoteObjectInterface = NSXPCInterface(with: F4JITHost.self)
        connection.resume()
        self.connection = connection
        host = connection.remoteObjectProxy as? F4JITHost
        // XPC connects lazily: sending a message is what lets the host accept this connection and reply with enable().
        host?.preparation("Helper connected.")
    }

    func enable(_ pid: Int32, pairing: Data) {
        queue.async { [self] in
            // One request, and only for the process that launched us.
            guard !accepted, pid > 0, pid != getpid(), pid == connection?.processIdentifier else {
                host?.finished("The JIT request did not match its host process."); return
            }
            accepted = true
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("pairing-\(UUID()).plist")
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                try JITPairing.validate(pairing)
                try pairing.write(to: file, options: [.atomic, .completeFileProtection])
                guard let script = Bundle.main.url(forResource: "madeira-jit", withExtension: "js") else { throw CocoaError(.fileNoSuchFile) }
                let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                try StikJIT.enableJIT(
                    targetPID: pid, pairingFile: file,
                    ddiPaths: DDIPaths.default(in: library.appendingPathComponent("StikJIT")),
                    script: .custom(script), forceScript: true,
                    preparationProgress: { [self] stage in
                        switch stage {
                        case .checkingReachability: host?.preparation("Checking the connection (the tunnel must be on).")
                        case .checkingDDI: host?.preparation("Checking Apple's developer support files.")
                        case .downloadingDDI: host?.preparation("Downloading Apple's developer support files.")
                        case .mountingDDI: host?.preparation("Preparing this device for debugging.")
                        case .verifyingDDI: host?.preparation("Checking device preparation.")
                        case .ready: host?.preparation("Attaching and starting the JIT script.")
                        @unknown default: host?.preparation("Preparing JIT.")
                        }
                    },
                    progress: { _ in })   // raw framework output can contain paths and protocol detail; it stays in this process
                host?.finished(nil)
            } catch {
                host?.finished("JIT failed: check that the tunnel (or LocalDevVPN) is on and the pairing file is current.")
            }
        }
    }
}
