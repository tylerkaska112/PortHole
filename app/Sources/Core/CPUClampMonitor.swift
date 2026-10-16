// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import UIKit

/// Tells whether iOS has slowed the phone's fast (performance) cores while the game runs.
///
/// The clock is cycles / time of the process on the fast cores (the same numbers the engine's [xp] log line uses). After a few minutes of load iOS pins those cores at about
/// 1.09 GHz, whatever the thermal state says, and the game loses roughly half its speed; the slow cores are not touched. A low clock means little without load (the cores
/// idle down), so it only counts while the game keeps the fast cores busy: half a core or more. Three seconds in a row below 1.3 GHz = clamped; two seconds above
/// 1.8 GHz = free again.
@MainActor
final class CPUClampMonitor: ObservableObject {
    static let shared = CPUClampMonitor()
    enum State { case measuring, light, full, clamped }

    @Published private(set) var state: State = .measuring
    /// The fast cores' clock over the last second of load (GHz); 0 before the first measurement.
    @Published private(set) var ghz: Double = 0
    @Published private(set) var clampedSince: Date?
    /// How long the whole session has been clamped, summed (seconds).
    private(set) var clampedTotal: TimeInterval = 0
    private(set) var sessionStart = Date()
    /// Seconds from the start of the game to the first clamp, nil while none happened.
    private(set) var firstClampAfter: TimeInterval?

    /// iOS's thermal pressure level (finer than ProcessInfo.thermalState): 0 nominal, then light, moderate, heavy; -1 when unreadable.
    @Published private(set) var pressure = -1
    private var timer: Timer?
    private var ticks = 0
    /// Share of the game's processor time that ran on the fast cores in the last second (0...1), -1 before the first measurement.
    @Published private(set) var fastShare: Double = -1
    /// Processor energy the game has used since it started (joules, the system's own estimate), and what it had used when the fast cores were first held back.
    @Published private(set) var energyJ: Double = 0
    private(set) var energyAtFirstClamp: Double?
    private var energy0: Double?
    /// Median of 17 runs of one game: the clamp came after about this much processor energy, whatever the time, the heat or the settings (139-160 J in 14 of them).
    static let observedBudgetJ = 150.0
    private var prev: (pms: Double, cyc: Double, wall: Double, all: Double)?
    private var low = 0, high = 0

    func start() {
        guard timer == nil else { return }
        energy0 = nil; energyJ = 0; energyAtFirstClamp = nil
        state = .measuring; ghz = 0; clampedSince = nil; clampedTotal = 0; firstClampAfter = nil; prev = nil; low = 0; high = 0
        sessionStart = Date(); ticks = 0
        logDiag("session start")
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let since = clampedSince { clampedTotal += Date().timeIntervalSince(since) }
        if clampedTotal > 0 || firstClampAfter != nil {
            LogStore.shared.log(String(format: "[clamp] session end: fast cores clamped for %.0f s in total; first clamp %@", clampedTotal,
                                       firstClampAfter.map { String(format: "%.0f s after the start", $0) } ?? "never"))
        }
        clampedSince = nil
    }

    static func pressureName(_ v: Int) -> String {
        switch v { case 0: "nominal"; case 1, 10: "light"; case 2, 20: "moderate"; case 3, 30: "heavy"; case 4, 40: "trapping"; case 5, 50: "sleeping"; case -1: "unreadable"; default: "level \(v)" }
    }
    /// One log line with everything the app can see of why the system might slow the processor: thermal levels, battery state and temperature, Low Power Mode.
    private func logDiag(_ why: String) {
        var buf = [CChar](repeating: 0, count: 400)
        clamp_diag_text(&buf, 400)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let b = UIDevice.current
        let state: String = { switch b.batteryState { case .charging: "charging"; case .full: "full"; case .unplugged: "unplugged"; default: "?" } }()
        LogStore.shared.log(String(format: "[clamp-diag] %@: heat %@, pressure %@ (%d), fast cores carry %.0f%% of the work, %.0f J used, battery %.0f%% %@, low power mode %@, iOS %@ | %@", why, Self.thermalName,
                                   Self.pressureName(pressure), pressure, fastShare * 100, energyJ, Double(b.batteryLevel) * 100, state,
                                   ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off", b.systemVersion, String(cString: buf)))
    }

    /// Auto power mode ended its break: forget the old clamp so the next reading starts fresh.
    func resetClamp() {
        if let since = clampedSince { clampedTotal += Date().timeIntervalSince(since) }
        clampedSince = nil; state = .measuring; low = 0; high = 0
    }

    private func tick() {
        defer { PowerManager.shared.autoTick(clamped: state == .clamped, pressure: pressure) }
        ticks += 1
        pressure = Int(clamp_thermal_pressure())
        if ticks % 15 == 0 { logDiag(state == .clamped ? "clamped" : "running") }
        var pms = 0.0, cyc = 0.0, wall = 0.0, all = 0.0, nj = 0.0
        guard cpu_clock_sample(&pms, &cyc, &wall, &all, &nj) == 0 else { return }
        if energy0 == nil { energy0 = nj }
        energyJ = (nj - (energy0 ?? nj)) / 1e9
        defer { prev = (pms, cyc, wall, all) }
        guard let p = prev else { return }
        let dt = wall - p.wall, dp = pms - p.pms, dc = cyc - p.cyc, da = all - p.all
        if da > 100 { fastShare = min(1, max(0, dp / da)) }
        guard dt > 200 else { return }
        let busy = dp / dt                                   // fast-core seconds per second
        guard busy >= 0.5, dp > 0 else {                      // not enough load to say anything
            if state != .clamped { state = busy > 0.05 ? .light : state == .measuring ? .measuring : .light }
            high = 0; if state == .clamped { low = max(low, 3) }
            return
        }
        let g = dc / (dp * 1e6)                              // cycles per ms / 1e6 = GHz
        ghz = g
        if g <= 1.3 {
            low += 1; high = 0
            if low >= 3, state != .clamped {
                state = .clamped; clampedSince = Date()
                if firstClampAfter == nil { firstClampAfter = Date().timeIntervalSince(sessionStart); energyAtFirstClamp = energyJ }
                LogStore.shared.log(String(format: "[clamp] iOS holds the fast cores at %.2f GHz (thermal %@) %.0f s after the start, after %.0f J of processor energy", g, Self.thermalName, Date().timeIntervalSince(sessionStart), energyJ))
                logDiag("clamp started")
            }
        } else if g >= 1.8 {
            high += 1; low = 0
            if state == .clamped, high >= 2 {
                if let since = clampedSince { clampedTotal += Date().timeIntervalSince(since) }
                LogStore.shared.log(String(format: "[clamp] the fast cores run free again at %.2f GHz after %.0f s clamped", g, clampedSince.map { Date().timeIntervalSince($0) } ?? 0))
                clampedSince = nil; state = .full
            } else if state != .clamped { state = .full }
        } else if state != .clamped { state = .full }
    }

    static var thermalName: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "cool"
        case .fair: "warm"
        case .serious: "hot"
        case .critical: "very hot"
        @unknown default: "?"
        }
    }
}
