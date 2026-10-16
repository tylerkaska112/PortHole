// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import GameController

/// Waits for the person to press a button (or push a stick) on a controller and says which one, by the names keyboard-and-mouse binds use ("A", "LB", "D↑", "LS"...).
/// It only reads the controller's state, so it leaves the menus' own controller handling alone, and while it listens the menus are told to ignore the controller
/// (otherwise the press would also select a row or go back).
@MainActor final class PadPressListener: ObservableObject {
    @Published private(set) var listening = false
    private var timer: Timer?
    private var armed = false
    private var onPress: ((String) -> Void)?
    private var navWasEnabled = true
    private var started: TimeInterval = 0

    func start(_ handler: @escaping (String) -> Void) {
        stop()
        guard !GCController.controllers().isEmpty else { handler(""); return }          // "" = no controller connected
        onPress = handler
        listening = true; armed = false
        started = ProcessInfo.processInfo.systemUptime
        navWasEnabled = NavHub.shared.enabled
        NavHub.shared.enabled = false
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        guard listening else { return }
        listening = false
        let restore = navWasEnabled
        // The press that ended the wait is still down: give the menus their controller back a moment later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NavHub.shared.enabled = restore }
    }

    private func poll() {
        if ProcessInfo.processInfo.systemUptime - started > 20 { stop(); onPress?("-"); return }       // "-" = gave up
        var pressed: String?
        for pad in GCController.controllers().compactMap(\.extendedGamepad) {
            if let name = Self.pressed(pad) { pressed = name; break }
        }
        if pressed == nil { armed = true; return }            // wait until everything is let go, so the button that opened this is not taken
        guard armed, let name = pressed else { return }
        stop()
        onPress?(name)
    }

    private static func pressed(_ pad: GCExtendedGamepad) -> String? {
        let buttons: [(String, GCControllerButtonInput?)] = [("A", pad.buttonA), ("B", pad.buttonB), ("X", pad.buttonX), ("Y", pad.buttonY), ("LB", pad.leftShoulder), ("RB", pad.rightShoulder),
                                                              ("L3", pad.leftThumbstickButton), ("R3", pad.rightThumbstickButton), ("Menu", pad.buttonMenu), ("View", pad.buttonOptions),
                                                              ("D\u{2191}", pad.dpad.up), ("D\u{2193}", pad.dpad.down), ("D\u{2190}", pad.dpad.left), ("D\u{2192}", pad.dpad.right)]
        for (name, button) in buttons where button?.isPressed == true { return name }
        if pad.leftTrigger.value > 0.6 { return "LT" }
        if pad.rightTrigger.value > 0.6 { return "RT" }
        if hypot(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value) > 0.75 { return "LS" }
        if hypot(pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value) > 0.75 { return "RS" }
        return nil
    }
}
