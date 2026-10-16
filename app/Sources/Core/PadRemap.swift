// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Which controller button a game sees for each physical one, in the modes where the pad reaches the game as a controller (Xbox pad, HID DualSense).
/// `map[physical] = output`, both using the names of PadActions.buttons ("A", "LB", "LT", "D↑"...); "none" makes a button do nothing. A button that is not in the map
/// stays itself, so a swap needs both directions (A -> B and B -> A). The triggers keep their analog value when they stay triggers.
struct PadRemap: Equatable {
    var map: [String: String]

    /// The Xbox button bits of the XInput state, as PadInput publishes them.
    static let bits: [String: UInt16] = [
        "A": 0x1000, "B": 0x2000, "X": 0x4000, "Y": 0x8000, "LB": 0x0100, "RB": 0x0200, "L3": 0x0040, "R3": 0x0080,
        "Menu": 0x0010, "View": 0x0020, "D\u{2191}": 0x0001, "D\u{2193}": 0x0002, "D\u{2190}": 0x0004, "D\u{2192}": 0x0008,
    ]
    /// A trigger counts as pressed (as a button) from about 30 % travel, the same threshold keyboard-and-mouse mode uses.
    static let triggerPressed: UInt8 = 77

    /// The targets a button can be given: every button, and nothing.
    static let targets: [String] = PadActions.buttons + ["none"]

    var isEmpty: Bool { map.allSatisfy { $0.key == $0.value } }

    /// What the game sees for a physical state. The sticks are not touched.
    func apply(buttons: UInt16, lt: UInt8, rt: UInt8) -> (buttons: UInt16, lt: UInt8, rt: UInt8) {
        var outButtons: UInt16 = 0, outLT: UInt8 = 0, outRT: UInt8 = 0
        func emit(_ target: String, pressed: Bool, analog: UInt8?) {
            guard pressed, target != "none" else { return }
            switch target {
            case "LT": outLT = max(outLT, analog ?? 255)
            case "RT": outRT = max(outRT, analog ?? 255)
            default: if let bit = Self.bits[target] { outButtons |= bit }
            }
        }
        for (name, bit) in Self.bits { emit(map[name] ?? name, pressed: buttons & bit != 0, analog: nil) }
        emit(map["LT"] ?? "LT", pressed: lt > Self.triggerPressed || (map["LT"] ?? "LT") == "LT" && lt > 0, analog: map["LT"] == nil || map["LT"] == "LT" || map["LT"] == "RT" ? lt : nil)
        emit(map["RT"] ?? "RT", pressed: rt > Self.triggerPressed || (map["RT"] ?? "RT") == "RT" && rt > 0, analog: map["RT"] == nil || map["RT"] == "RT" || map["RT"] == "LT" ? rt : nil)
        return (outButtons, outLT, outRT)
    }
}
