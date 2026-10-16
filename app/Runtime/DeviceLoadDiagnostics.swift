// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
//
// DeviceLoadDiagnostics, copied from Madeira's app/Madeira/Library.swift (upstream a2e... "[device-load]" diagnostics, #317/#318). That file is Madeira's own
// SwiftUI library screen and is not vendored; the vendored LogStore.swift now calls this enum for its thermal-transition lines. Re-copy the enum when upstream changes it.
import Foundation
import UIKit
import QuartzCore

/// Thermal state, Low Power Mode, screen capture, battery and brightness every
/// 10 s while a session runs: the device conditions that explain a slow run in
/// a log (447: the CPU was held at 1.31/1.70 GHz from the start of play with
/// thermal=nominal; charging and screen recording also draw from the power
/// budget). MADEIRA_DEVICE_STATS=0 turns the line off.
enum DeviceLoadDiagnostics {
    private static var lastReport = 0.0
    private static var timer: Timer?
    /// Opt-in (env.MADEIRA_DEVICE_STATS = 1): a line every 10 s during every
    /// session is a diagnostic, so it is off by default.
    static func start() {
        guard timer == nil, MadeiraConfig.flag("MADEIRA_DEVICE_STATS", fallback: false) else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let value = Timer(timeInterval: 10, repeats: true) { _ in report() }
        timer = value
        RunLoop.main.add(value, forMode: .common)
    }
    static func report() {
        guard wine_process_is_running() != 0 else { return }
        let now = CACurrentMediaTime()
        guard now - lastReport >= 10 else { return }
        lastReport = now
        let process = ProcessInfo.processInfo
        let thermal = thermalName(process.thermalState)
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled { device.isBatteryMonitoringEnabled = true }   // the HUD turns it off when it closes
        let level = device.batteryLevel < 0 ? "?" : String(Int((device.batteryLevel * 100).rounded()))
        let battery: String
        switch device.batteryState {
        case .charging: battery = "charging"
        case .full: battery = "full"
        case .unplugged: battery = "unplugged"
        default: battery = "unknown"
        }
        fputs("[device-load] thermal=\(thermal) low-power=\(process.isLowPowerModeEnabled ? 1 : 0) capture=\(UIScreen.main.isCaptured ? 1 : 0) "
              + "battery=\(level)% \(battery) brightness=\(String(format: "%.2f", UIScreen.main.brightness))\n", stderr)
    }
    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
