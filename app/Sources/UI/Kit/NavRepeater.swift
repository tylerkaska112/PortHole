// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Turns what the D-pad and the left stick are doing into navigation steps: one step when a direction is first pushed, then repeats while it is held, faster the longer it is held.
/// The two sources are tracked separately (releasing the D-pad must not cancel a held stick, and the other way round) but only one repeats at a time, the D-pad first.
/// The stick has hysteresis: it has to be pushed well past the edge to start and let well back to stop, and it stays on the direction it was pushed in until the other axis clearly wins,
/// so a thumb resting near a diagonal does not flutter between two directions.
struct NavRepeater {
    var firstDelay: TimeInterval = 0.40
    var interval: TimeInterval = 0.14
    var fastInterval: TimeInterval = 0.07
    var fastAfter = 6
    var stickEngage: Float = 0.60
    var stickRelease: Float = 0.35
    var dominance: Float = 1.25

    private var dpad: NavDirection?
    private var stick: NavDirection?
    private var active: NavDirection?
    private var nextFire: TimeInterval = 0
    private var count = 0

    /// True while a direction is held, so the caller keeps ticking.
    var isHolding: Bool { active != nil }

    mutating func reset() { dpad = nil; stick = nil; active = nil; count = 0 }

    mutating func updateDPad(x: Float, y: Float, now: TimeInterval) -> [NavDirection] {
        dpad = Self.direction(x: x, y: y, threshold: 0.5, dominance: 1.0, current: nil)
        return settle(now: now)
    }

    mutating func updateStick(x: Float, y: Float, now: TimeInterval) -> [NavDirection] {
        let threshold = stick == nil ? stickEngage : stickRelease
        stick = Self.direction(x: x, y: y, threshold: threshold, dominance: dominance, current: stick)
        return settle(now: now)
    }

    /// Call every few milliseconds while `isHolding`: the repeats that are due.
    mutating func tick(now: TimeInterval) -> [NavDirection] {
        guard let d = active, now >= nextFire else { return [] }
        count += 1
        nextFire = now + (count >= fastAfter ? fastInterval : interval)
        return [d]
    }

    private mutating func settle(now: TimeInterval) -> [NavDirection] {
        let wanted = dpad ?? stick
        guard wanted != active else { return [] }
        active = wanted
        count = 0
        guard let wanted else { return [] }
        nextFire = now + firstDelay
        return [wanted]
    }

    /// nil inside the dead zone. With a `current` direction, the other axis has to beat it by `dominance` before the direction changes.
    static func direction(x: Float, y: Float, threshold: Float, dominance: Float, current: NavDirection?) -> NavDirection? {
        let ax = abs(x), ay = abs(y)
        guard max(ax, ay) >= threshold else { return nil }
        let horizontal: Bool
        switch current {
        case .left?, .right?: horizontal = !(ay > ax * dominance)
        case .up?, .down?: horizontal = ax > ay * dominance
        case nil: horizontal = ax >= ay
        }
        return horizontal ? (x > 0 ? .right : .left) : (y > 0 ? .up : .down)
    }
}
