// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import Network

/// Whether the device has a network at all (airplane mode, no Wi-Fi and no cellular). Screens use it to say "offline" calmly and to keep their saved lists, instead
/// of showing a red error for something that was never going to work. Being online says nothing about whether one particular server answers.
@MainActor
final class NetworkStatus: ObservableObject {
    static let shared = NetworkStatus()
    @Published private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                if self?.isOnline != online { self?.isOnline = online }
            }
        }
        monitor.start(queue: DispatchQueue(label: "site.portholehq.network-status", qos: .utility))
    }
}
