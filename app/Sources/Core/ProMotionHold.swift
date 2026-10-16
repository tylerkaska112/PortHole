// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import UIKit

/// Keeps a ProMotion screen at its top refresh rate while a game runs (Settings > Engine options > Hold the screen at its top refresh rate).
/// A frame the game finishes between two 60 Hz refreshes otherwise waits for the next one; at 120 Hz it lands sooner. Off by default because it costs battery.
/// It only asks the system for the rate with a display link that does nothing; the game's own frame cap is not touched.
@MainActor
final class ProMotionHold {
    static let shared = ProMotionHold()
    private var link: CADisplayLink?
    /// Does nothing to the game; counts its own callbacks so the log says what rate the screen really runs at (the system may grant less than asked: hot device, low power).
    private final class Ticker: NSObject {
        private var start = 0.0, count = 0
        @objc func tick(_ l: CADisplayLink) {
            if start == 0 { start = l.timestamp; return }
            count += 1
            let dt = l.timestamp - start
            guard dt >= 5 else { return }
            let hz = Double(count) / dt
            let thermal = ProcessInfo.processInfo.thermalState.rawValue
            let low = ProcessInfo.processInfo.isLowPowerModeEnabled
            Task { @MainActor in LogStore.shared.log("[promote] the screen ran at \(String(format: "%.0f", hz)) Hz over the last \(String(format: "%.0f", dt)) s (thermal \(thermal), low power \(low))") }
            start = l.timestamp; count = 0
        }
    }
    private let ticker = Ticker()

    /// Called at the start of a game: arms the hold when the option is on and the screen can go above 60 Hz.
    /// Performance mode asks for the hold too (it presents at the screen's maximum, which only happens if the screen is allowed to run that fast).
    private var performance = false
    /// Frame generation needs the screen at its top rate (it shows two pictures per game frame).
    var frameGeneration = false
    func setPerformance(_ on: Bool) {
        guard on != performance else { return }
        performance = on
        if on { begin() } else if EngineOptions.value("env.MADEIRA_PROMOTE") != "1" { end() }
    }

    func begin() {
        guard EngineOptions.value("env.MADEIRA_PROMOTE") == "1" || performance || frameGeneration, UIScreen.main.maximumFramesPerSecond > 60 else { end(); return }
        guard link == nil else { return }
        let max = Float(UIScreen.main.maximumFramesPerSecond)
        let l = CADisplayLink(target: ticker, selector: #selector(Ticker.tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: max, preferred: max)
        l.add(to: .main, forMode: .common)
        link = l
        LogStore.shared.log("[promote] holding the screen at \(Int(max)) Hz")
    }

    /// Frame generation switched on or off while the game runs (the in-game menu).
    func setFrameGeneration(_ on: Bool) {
        frameGeneration = on
        if on { begin() } else if EngineOptions.value("env.MADEIRA_PROMOTE") != "1" && !performance { end() }
    }

    func end() { link?.invalidate(); link = nil; performance = false; frameGeneration = false }
}
