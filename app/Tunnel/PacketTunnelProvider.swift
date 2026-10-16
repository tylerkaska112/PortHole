// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import NetworkExtension

/// A loopback tunnel. StikJIT reaches the device's own debug service at 10.7.0.1; this makes that address bounce back to the phone itself.
///
/// The tunnel interface is 10.7.0.0/24 and only that subnet is routed here. A packet the helper sends to 10.7.0.1 arrives with source 10.7.0.0 and
/// destination 10.7.0.1; swapping the two addresses and writing it back makes the phone's own network stack receive it "from 10.7.0.1", deliver it to its
/// local listener, and send the reply the same way. IP and TCP/UDP checksums cover the addresses as a symmetric sum, so swapping them leaves every
/// checksum valid and nothing needs recomputing. IPv4 only; nothing else is routed here, so it does not carry or see any other traffic.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let localAddress = "10.7.0.0"

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: localAddress)
        let ipv4 = NEIPv4Settings(addresses: [localAddress], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: localAddress, subnetMask: "255.255.255.0")]
        settings.ipv4Settings = ipv4
        settings.mtu = 1500
        setTunnelNetworkSettings(settings) { [weak self] error in
            if error == nil { self?.bounce() }
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    /// Read packets from the tunnel, swap source and destination, write them straight back.
    private func bounce() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            var out: [Data] = []
            var outProtocols: [NSNumber] = []
            for (index, packet) in packets.enumerated() {
                guard packet.count >= 20, packet[packet.startIndex] >> 4 == 4 else { continue }   // IPv4 header only
                var swapped = packet
                swapped.withUnsafeMutableBytes { raw in
                    let bytes = raw.bindMemory(to: UInt8.self)
                    for offset in 0..<4 { bytes.swapAt(12 + offset, 16 + offset) }                 // source <-> destination
                }
                out.append(swapped)
                outProtocols.append(protocols[index])
            }
            if !out.isEmpty { self.packetFlow.writePackets(out, withProtocols: outProtocols) }
            self.bounce()
        }
    }
}
