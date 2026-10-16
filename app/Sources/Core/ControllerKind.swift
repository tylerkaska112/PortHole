// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// What kind of controller is in the player's hands, so the on-screen guides name its buttons the way they are printed on it: a PlayStation pad has ✕ ○ □ △ and L1 / R1,
/// an Xbox pad A B X Y and LB / RB, a Nintendo pad has its own letters. Everything inside the app (focus commands, binds, remaps) keeps using the Xbox names; this only
/// changes what is shown. Pure logic, host-tested.
enum ControllerKind: Equatable {
    case none, xbox, dualSense, dualShock, switchPro, generic

    /// Decided from what iOS says about the controller: its product category and vendor name, and which profile class it came with.
    static func classify(productCategory: String, vendorName: String, dualSenseProfile: Bool, dualShockProfile: Bool, xboxProfile: Bool) -> ControllerKind {
        let text = (productCategory + " " + vendorName).lowercased()
        if dualSenseProfile || text.contains("dualsense") { return .dualSense }
        if dualShockProfile || text.contains("dualshock") || text.contains("ds4") { return .dualShock }
        if xboxProfile || text.contains("xbox") { return .xbox }
        if text.contains("switch") || text.contains("joy-con") || text.contains("joycon") || text.contains("pro controller") { return .switchPro }
        return .generic
    }

    var isPlayStation: Bool { self == .dualSense || self == .dualShock }

    var displayName: String {
        switch self {
        case .none: "No controller"
        case .xbox: "Xbox controller"
        case .dualSense: "DualSense"
        case .dualShock: "DualShock 4"
        case .switchPro: "Switch Pro Controller"
        case .generic: "Controller"
        }
    }

    /// A button's name as printed on this controller. `name` is the Xbox name the app uses everywhere ("A", "LB", "Menu", "View", "LT", "D↑"...).
    func glyph(_ name: String) -> String {
        switch self {
        case .dualSense, .dualShock:
            switch name {
            case "A": return "\u{2715}"            // ✕
            case "B": return "\u{25CB}"            // ○
            case "X": return "\u{25A1}"            // □
            case "Y": return "\u{25B3}"            // △
            case "LB": return "L1"
            case "RB": return "R1"
            case "LT": return "L2"
            case "RT": return "R2"
            case "Menu": return "Options"
            case "View": return self == .dualSense ? "Create" : "Share"
            default: return name
            }
        case .switchPro:
            // Nintendo prints the letters in other places: the bottom button is B, the right one A, the left one Y, the top one X.
            switch name {
            case "A": return "B"
            case "B": return "A"
            case "X": return "Y"
            case "Y": return "X"
            case "LB": return "L"
            case "RB": return "R"
            case "LT": return "ZL"
            case "RT": return "ZR"
            case "Menu": return "+"
            case "View": return "\u{2212}"          // −
            default: return name
            }
        case .xbox, .generic, .none:
            return name
        }
    }

    /// For lists that name buttons by their Xbox names: the name, with how this controller prints it when that differs ("A (✕)").
    func label(_ name: String) -> String {
        let g = glyph(name)
        return g == name ? name : "\(name) (\(g))"
    }

    /// The two-button menu chord (Menu + View) in this controller's words.
    var menuChordName: String { "\(glyph("Menu")) + \(glyph("View"))" }

    /// The button iOS keeps for the system on some pads.
    var homeName: String {
        switch self {
        case .dualSense, .dualShock: "the PS button"
        case .switchPro: "the Home button"
        default: "the Xbox button"
        }
    }
}
