// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// The size of the screen a game sees (Wine's virtual monitor). A game that asks for its own resolution can pick any size up to this one; one that uses the desktop's size
/// draws at exactly this size, and the picture is then scaled to the device's screen. Higher is sharper and costs memory and speed; lower is faster.
struct DisplayResolution: Equatable, Sendable {
    let width: Int
    let height: Int
    var text: String { "\(width) \u{00D7} \(height)" }

    static let fallback = DisplayResolution(width: 1280, height: 720)
    static let defaultID = "1280x720"
    /// Sizes everyone knows, smallest to largest.
    static let fixedIDs = ["640x360", "960x540", "1280x720", "1600x900", "1920x1080"]
    /// "Screen shape" sizes: the given height, with the width that matches this device's screen so the picture fills it without bars.
    static let shapeIDs = ["screen720", "screen1080"]
    static var allIDs: [String] { fixedIDs + shapeIDs }

    static let widthRange = 320...3840, heightRange = 180...2160

    /// The id if it is one the app offers, else nil. A size that used to be offered (2560x1440 in 0.50.19, where the game's window did not become the active one and ignored
    /// the mouse) is therefore treated as "not chosen", so it cannot stay selected out of sight.
    static func offered(_ id: String?) -> String? {
        guard let id, allIDs.contains(id) else { return nil }
        return id
    }

    /// The size an id stands for on a screen of this shape (width / height of the device in landscape). An id the app does not offer gives the default size.
    static func resolve(id: String?, screenAspect: Double) -> DisplayResolution {
        guard let id = offered(id) else { return fallback }
        if id.hasPrefix("screen"), let height = Int(id.dropFirst(6)), heightRange.contains(height) {
            let aspect = screenAspect.isFinite && screenAspect > 0 ? min(max(screenAspect, 1.0), 2.4) : 16.0 / 9.0
            let width = Int((Double(height) * aspect / 2).rounded()) * 2          // an even width: some games and shaders want it
            return DisplayResolution(width: min(max(width, widthRange.lowerBound), widthRange.upperBound), height: height)
        }
        let parts = id.split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), widthRange.contains(w), heightRange.contains(h) else { return fallback }
        return DisplayResolution(width: w, height: h)
    }

    /// The name shown in a menu.
    static func title(id: String, screenAspect: Double) -> String {
        let size = resolve(id: id, screenAspect: screenAspect)
        if id.hasPrefix("screen") { return "Screen shape, \(size.text)" }
        switch id {
        case "640x360": return "\(size.text) (fastest)"
        case defaultID: return "\(size.text) (default)"
        default: return size.text
        }
    }
}
