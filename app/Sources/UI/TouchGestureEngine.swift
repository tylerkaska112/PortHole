// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import CoreGraphics

enum MouseButton { case left, right }

/// Where the engine sends what it decides. Points are in the game view's coordinates; the view converts them to Wine desktop pixels.
protocol PointerSink: AnyObject {
    func pointerMove(_ p: CGPoint)
    func pointerPress(_ b: MouseButton, at p: CGPoint)
    func pointerRelease(_ b: MouseButton, at p: CGPoint)
    /// A complete press-and-release with a short hold (so a game that samples once per frame sees it).
    func pointerClick(_ b: MouseButton, at p: CGPoint)
    func pointerWheel(_ delta: Int32, at p: CGPoint)
}

/// Turns raw touches into mouse actions. Pure logic (no UIKit), so it can be tested with scripted touches.
///
///   tap                -> click with the primary button (left, or right in "right mode")
///   drag               -> primary button held from where the finger went down, until it lifts
///   press and hold     -> the OTHER button held (right, normally) until it lifts; moving while held drags it
///   two-finger tap     -> click with the other button, at the midpoint
///   two-finger pinch   -> mouse wheel (spread = zoom in)
///
/// No button is pressed on touch-down. The engine waits to learn whether the finger will tap, drag or hold; the cursor still moves to the finger at once,
/// so hover works. A second finger cancels a pending tap, so a two-finger gesture never leaves a stray click.
final class TouchGestureEngine {
    struct Config {
        var slop: CGFloat = 12              // points a finger may wander and still be a tap / hold
        var longPress: TimeInterval = 0.30  // hold this long -> the other button
        var tapMaxDuration: TimeInterval = 0.45  // a two-finger tap must be quicker than this
        var pinchStep: CGFloat = 0.10       // each 10% change in finger spacing = one wheel notch
    }

    var config = Config()
    var primary: MouseButton = .left
    weak var sink: PointerSink?

    private var secondary: MouseButton { primary == .left ? .right : .left }
    private var points: [Int: CGPoint] = [:]
    /// Fingers that joined while a button was held: they are ignored, and must not stop the held finger's lift from releasing the button.
    private var extras: Set<Int> = []

    private enum State {
        case idle
        case pending(id: Int, start: CGPoint, time: TimeInterval)
        case held(id: Int, button: MouseButton)
        case two(a: Int, b: Int, time: TimeInterval, lastSpacing: CGFloat, startMid: CGPoint, moved: Bool)
        case waitingForLift(remaining: Set<Int>)
    }
    private var state: State = .idle

    var isTouching: Bool { if case .idle = state { return false }; return true }

    // MARK: Touch events

    func began(_ id: Int, at p: CGPoint, time: TimeInterval) {
        points[id] = p
        switch state {
        case .idle:
            state = .pending(id: id, start: p, time: time)
            sink?.pointerMove(p)
        case .pending(let first, _, let t0):
            guard let a = points[first] else { return }
            _ = t0
            state = .two(a: first, b: id, time: time, lastSpacing: max(distance(a, p), 1), startMid: mid(a, p), moved: false)
        case .held:
            extras.insert(id)                                 // a finger joining a drag changes nothing
        case .two(let a, let b, _, _, _, _):
            state = .waitingForLift(remaining: [a, b, id])
        case .waitingForLift(var remaining):
            remaining.insert(id); state = .waitingForLift(remaining: remaining)
        }
    }

    func moved(_ id: Int, to p: CGPoint, time: TimeInterval) {
        points[id] = p
        switch state {
        case .pending(let first, let start, _) where first == id:
            if distance(start, p) > config.slop {
                sink?.pointerPress(primary, at: start)
                sink?.pointerMove(p)
                state = .held(id: id, button: primary)
            }
        case .held(let held, _) where held == id:
            sink?.pointerMove(p)
        case .two(let a, let b, let t0, let last, let startMid, let moved):
            guard let pa = points[a], let pb = points[b] else { return }
            let spacing = max(distance(pa, pb), 1)
            var newLast = last, didMove = moved
            if distance(mid(pa, pb), startMid) > config.slop { didMove = true }
            let ratio = spacing / last
            if abs(ratio - 1) >= config.pinchStep {
                let steps = max(1, Int(abs(ratio - 1) / config.pinchStep))
                sink?.pointerWheel(Int32(120 * steps) * (ratio > 1 ? 1 : -1), at: mid(pa, pb))
                newLast = spacing; didMove = true
            }
            state = .two(a: a, b: b, time: t0, lastSpacing: newLast, startMid: startMid, moved: didMove)
        default: break
        }
    }

    func ended(_ id: Int, at p: CGPoint, time: TimeInterval) {
        points[id] = p
        defer { points[id] = nil; if case .idle = state { points.removeAll(); extras.removeAll() } }
        if case .held = state, extras.remove(id) != nil { return }   // an ignored extra finger lifted
        switch state {
        case .pending(let first, _, _) where first == id:
            sink?.pointerClick(primary, at: p)
            state = .idle
        case .held(let held, let button) where held == id:
            sink?.pointerRelease(button, at: p)
            state = extras.isEmpty ? .idle : .waitingForLift(remaining: extras)
            extras = []
        case .two(let a, let b, let t0, _, _, let moved) where id == a || id == b:
            if !moved && time - t0 <= config.tapMaxDuration, let pa = points[a], let pb = points[b] {
                sink?.pointerClick(secondary, at: mid(pa, pb))
            }
            state = .waitingForLift(remaining: [a, b].filter { $0 != id }.reduce(into: Set<Int>()) { $0.insert($1) })
        case .waitingForLift(var remaining):
            remaining.remove(id)
            state = remaining.isEmpty ? .idle : .waitingForLift(remaining: remaining)
        default: break
        }
    }

    /// The system took the touch away: release anything held and send no click.
    func cancelled(_ id: Int) {
        let p = points[id] ?? .zero
        switch state {
        case .held(let held, let button) where held == id:
            sink?.pointerRelease(button, at: p)
            state = extras.isEmpty ? .idle : .waitingForLift(remaining: extras)
            extras = []
        case .held where extras.contains(id): extras.remove(id)
        case .pending(let first, _, _) where first == id: state = .idle
        case .two(let a, let b, _, _, _, _) where id == a || id == b:
            state = .waitingForLift(remaining: [a, b].filter { $0 != id }.reduce(into: Set<Int>()) { $0.insert($1) })
        case .waitingForLift(var remaining): remaining.remove(id); state = remaining.isEmpty ? .idle : .waitingForLift(remaining: remaining)
        default: break
        }
        points[id] = nil
        if case .idle = state { points.removeAll(); extras.removeAll() }
    }

    /// Call a few times a second while touching: promotes a held finger to the other button.
    func tick(time: TimeInterval) {
        guard case .pending(let id, let start, let t0) = state, time - t0 >= config.longPress else { return }
        sink?.pointerPress(secondary, at: start)
        state = .held(id: id, button: secondary)
    }

    // MARK: Helpers

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    private func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
}
