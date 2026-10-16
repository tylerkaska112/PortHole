// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import UIKit

/// How hard the game is allowed to work. Three presets over the levers the runtime already has:
///   * frame cap: Performance runs at the screen's own maximum (120 on a ProMotion screen, DXMT's vsync mode 0 "MAX"; 60 on a 60 Hz screen, mode 1), Balanced and Saver
///     at 30 (mode 3). Factorio simulates at 60 updates/s whatever it draws, so 30 FPS costs
///     little to look at and roughly halves the GPU work.
///   * ECO: the runtime puts every guest thread on a low QoS class, so the scheduler prefers the efficiency cores at lower clocks: the same work
///     takes longer but costs much less energy (the runtime's own measurements are in wine/dlls/ntdll/unix/sync.c, "ml1133").
/// Plus a thermal guard: when iOS reports the phone as `serious` or worse, the effective mode drops to Battery saver until it cools.
enum PowerMode: Int, CaseIterable {
    case performance, balanced, saver
    /// Locked 60 FPS (no 120 Hz hold) while iOS lets the fast cores run, a steady 30 FPS for a while once it holds them back (see PowerManager.autoTick).
    case auto

    var title: String {
        switch self {
        case .performance: "Performance"
        case .balanced: "Balanced"
        case .saver: "Battery saver"
        case .auto: "Auto"
        }
    }
    /// The refresh rate the screen can reach (120 on ProMotion, otherwise 60).
    static var screenMaxFPS: Int { max(60, UIScreen.main.maximumFramesPerSecond) }
    var detail: String {
        switch self {
        case .performance: PowerMode.screenMaxFPS > 60 ? "up to \(PowerMode.screenMaxFPS) FPS" : "60 FPS"
        case .balanced: "30 FPS"
        case .saver: "30 FPS + Eco"
        case .auto: "60 FPS, steady 30 when the phone slows down"
        }
    }
}

final class PowerManager {
    static let shared = PowerManager()
    static let didChange = Notification.Name("PowerManagerDidChange")

    private let key = "f4.powerMode"
    private(set) var userMode: PowerMode
    private(set) var thermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    private var running = false

    private init() {
        let stored = UserDefaults.standard.object(forKey: key) as? Int
        userMode = stored.flatMap(PowerMode.init(rawValue:)) ?? .balanced
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.thermal = ProcessInfo.processInfo.thermalState
            LogStore.shared.log("[power] thermal state: \(self.thermalName)")
            self.apply()
        }
    }

    /// "Keep my power mode when the phone is hot": skips the automatic drop to Battery saver (and its Eco mode) at "hot". "Very hot" still forces it.
    static let ignoreHeatKey = "f4.ignoreHeatLimit"
    private(set) var ignoreHeat = UserDefaults.standard.bool(forKey: PowerManager.ignoreHeatKey)
    /// What the running game uses when it has its own settings; cleared when the session ends. Never written to the saved (global) choice.
    private var sessionMode: PowerMode?
    private var sessionKeepHot: Bool?
    func beginSession(mode: PowerMode, keepWhenHot: Bool) { sessionMode = mode; sessionKeepHot = keepWhenHot }
    /// The mode this session (or, outside a game, the saved choice) asks for, before any heat override.
    var chosen: PowerMode { sessionMode ?? userMode }
    private var mode: PowerMode { chosen }
    private var keepHot: Bool { sessionKeepHot ?? ignoreHeat }
    func setIgnoreHeat(_ on: Bool) {
        guard on != ignoreHeat else { return }
        ignoreHeat = on
        UserDefaults.standard.set(on, forKey: Self.ignoreHeatKey)
        LogStore.shared.log("[power] keep my mode when hot: \(on ? "ON" : "off")")
        apply()
    }

    /// The mode in force right now: the person's choice, raised to Battery saver when the phone is hot (unless they chose to keep it; very hot always forces it).
    var effective: PowerMode {
        let base: PowerMode = mode == .auto ? (autoCool ? .balanced : .performance) : mode
        switch thermal {
        case .critical: return .saver
        case .serious: return keepHot ? base : .saver
        default: return base
        }
    }

    // MARK: Auto
    /// Auto mode is in its steady-30 break (Balanced) right now.
    private(set) var autoCool = false
    private var coolUntil = Date.distantPast, lastCoolEnd = Date.distantPast
    private var coolRounds = 0

    /// Once a second from CPUClampMonitor while a game runs. Auto plays like Performance (locked 60 FPS, no 120 Hz hold) until iOS holds the fast cores back, then drops to Balanced
    /// (a steady 30; in the logs a clamped phone still managed ~28 there, while Performance judders at 20-25 and Battery saver's Eco put the game on the slow cores: 12-22 FPS).
    /// After 60 s it tries the fast cores again; if it is clamped again within 150 s the break is longer (120, 180, 300 s). Pressure only extends the break when it is heavy (30+).
    func autoTick(clamped: Bool, pressure: Int) {
        guard running, chosen == .auto else {
            if autoCool { autoCool = false; apply() }
            return
        }
        let now = Date()
        if !autoCool {
            guard clamped else { return }
            coolRounds = now.timeIntervalSince(lastCoolEnd) < 150 ? min(coolRounds + 1, 3) : 0
            let secs = [60.0, 120, 180, 300][coolRounds]
            coolUntil = now.addingTimeInterval(secs); autoCool = true
            LogStore.shared.log("[power] Auto: steady 30 FPS for \(Int(secs)) s (fast cores held back, thermal pressure \(pressure))")
            apply()
        } else if now >= coolUntil {
            if pressure >= 30 { coolUntil = now.addingTimeInterval(20); return }
            autoCool = false; lastCoolEnd = now
            LogStore.shared.log("[power] Auto: trying 60 FPS again")
            Task { @MainActor in CPUClampMonitor.shared.resetClamp() }
            apply()
        }
    }

    var thermalName: String {
        switch thermal {
        case .nominal: "cool"
        case .fair: "warm"
        case .serious: "hot"
        case .critical: "very hot"
        @unknown default: "?"
        }
    }

    /// 30 FPS needs DXMT's display-pacing hook; without it the 30 setting would run uncapped, so fall back to 60.
    private static let has30Cap: Bool = {
        madeira_set_display_max_fps(Int32(UIScreen.main.maximumFramesPerSecond), 0)
        return madeira_dxmt_has_display_pacing() != 0
    }()

    func set(_ mode: PowerMode) {
        guard mode != userMode else { return }
        userMode = mode
        UserDefaults.standard.set(userMode.rawValue, forKey: key)
        apply()
    }

    /// Picks a mode from the in-game menu: during a game it is for this session only (like `cycle()`), otherwise it is the saved choice.
    func setForSession(_ mode: PowerMode) {
        if running { guard sessionMode != mode else { return }; sessionMode = mode; apply() } else { set(mode) }
    }

    func cycle() {
        let all = PowerMode.allCases
        if running {            // during a game: change this session only, not the saved choice
            sessionMode = all[(all.firstIndex(of: mode)! + 1) % all.count]
        } else {
            userMode = all[(all.firstIndex(of: userMode)! + 1) % all.count]
            UserDefaults.standard.set(userMode.rawValue, forKey: key)
        }
        apply()
    }

    /// Starts applying the settings (call when a game starts) and re-applies on every change.
    func start() { running = true; apply() }
    func stop() { running = false; sessionMode = nil; sessionKeepHot = nil; autoCool = false; coolRounds = 0; DispatchQueue.main.async { ProMotionHold.shared.setPerformance(false) } }

    private func apply() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        guard running else { return }
        let mode = effective
        // Performance: present as fast as the screen refreshes (mode 0, "MAX") when it goes above 60 Hz, otherwise locked 60. The screen is held at its maximum rate to match.
        let fast = PowerMode.screenMaxFPS > 60
        let autoBurst = chosen == .auto && mode == .performance        // Auto's fast phase: locked 60, the screen is not held at 120 Hz
        let cap: Int32 = mode == .performance ? (fast && !autoBurst ? 0 : 1) : (Self.has30Cap ? 3 : 1)
        madeira_set_vsync_locked(cap)                                  // read per present, safe to change while the game runs
        let hold = mode == .performance && fast && !autoBurst
        DispatchQueue.main.async { ProMotionHold.shared.setPerformance(hold) }
        madeira_set_display_max_fps(Int32(UIScreen.main.maximumFramesPerSecond), 0)
        madeira_set_eco(mode == .saver ? 1 : 0)
        LogStore.shared.log("[power] mode \(mode.title) (chosen \(mode.title), thermal \(thermalName)): cap \(cap == 3 ? "30" : cap == 0 ? "\(PowerMode.screenMaxFPS) (screen maximum)" : "60") FPS, eco \(mode == .saver ? "on" : "off")")
    }
}
