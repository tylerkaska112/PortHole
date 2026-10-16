// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import CoreGraphics

enum NavDirection: Equatable { case up, down, left, right }

/// Everything a controller (or keyboard) can ask of the interface.
enum NavCommand: Equatable {
    case move(NavDirection)
    case select           // A, Return
    case back             // B, Escape
    case menu             // Start / Menu: the game's quick actions
    case secondary        // X
    case tertiary         // Y
    case previousSection  // LB
    case nextSection      // RB
}

/// Which item the D-pad goes to. The rule is the one Android's focus finder uses, because it behaves the way people expect on grids and lists:
/// an item is a candidate only when it lies beyond the current one in that direction (its facing edge is past the current item's, not just its centre a little further along),
/// and among candidates the nearest wins, with sideways offset counted far less than distance in the direction of travel. Items lined up with the current one (their span
/// overlaps it across the direction of travel) beat items that are not, unless those are much nearer.
enum SpatialFocus {
    static func next<ID: Hashable>(from current: CGRect, among candidates: [(id: ID, frame: CGRect)], direction: NavDirection, excluding: ID? = nil, anchor: CGFloat? = nil) -> ID? {
        // Moving along one axis keeps its position across the other: a grid column stays a column even when the rows are different widths.
        let origin = anchored(current, direction: direction, anchor: anchor)
        var best: (id: ID, score: CGFloat)?
        for c in candidates where c.id != excluding {
            guard let s = score(from: origin, to: c.frame, direction: direction) else { continue }
            // Not lined up with the current item: it has to be about half as far to win (the score is on squares, so a factor of 4).
            let effective = linedUp(origin, c.frame, direction: direction) ? s : s * 4
            if best == nil || effective < best!.score { best = (c.id, effective) }
        }
        return best?.id
    }

    /// `current` with its centre moved to `anchor` across the direction of travel (nil keeps it where it is).
    static func anchored(_ r: CGRect, direction: NavDirection, anchor: CGFloat?) -> CGRect {
        guard let anchor else { return r }
        switch direction {
        case .up, .down: return CGRect(x: anchor - r.width / 2, y: r.minY, width: r.width, height: r.height)
        case .left, .right: return CGRect(x: r.minX, y: anchor - r.height / 2, width: r.width, height: r.height)
        }
    }

    /// Do the two spans overlap across the direction of travel (same column for up/down, same row for left/right)?
    static func linedUp(_ a: CGRect, _ b: CGRect, direction: NavDirection) -> Bool {
        switch direction {
        case .up, .down: return min(a.maxX, b.maxX) - max(a.minX, b.minX) > 1
        case .left, .right: return min(a.maxY, b.maxY) - max(a.minY, b.minY) > 1
        }
    }

    /// nil when the candidate is not beyond the current item in that direction at all.
    static func score(from a: CGRect, to b: CGRect, direction: NavDirection) -> CGFloat? {
        let tolerance: CGFloat = 2
        let major: CGFloat, minor: CGFloat
        switch direction {
        case .right:
            guard b.minX >= a.minX + tolerance, b.maxX > a.maxX + tolerance, b.minX >= a.midX else { return nil }
            major = max(0, b.minX - a.maxX); minor = abs(b.midY - a.midY)
        case .left:
            guard b.maxX <= a.maxX - tolerance, b.minX < a.minX - tolerance, b.maxX <= a.midX else { return nil }
            major = max(0, a.minX - b.maxX); minor = abs(b.midY - a.midY)
        case .down:
            guard b.minY >= a.minY + tolerance, b.maxY > a.maxY + tolerance, b.minY >= a.midY else { return nil }
            major = max(0, b.minY - a.maxY); minor = abs(b.midX - a.midX)
        case .up:
            guard b.maxY <= a.maxY - tolerance, b.minY < a.minY - tolerance, b.maxY <= a.midY else { return nil }
            major = max(0, a.minY - b.maxY); minor = abs(b.midX - a.midX)
        }
        // Distance along the way counts far more than sideways offset (Android's 13 : 1 on the squares); a touching neighbour has major 0, so the offset decides.
        return 13 * major * major + minor * minor
    }

    /// The item nearest to a point: where focus goes when the focused item disappears.
    static func nearest<ID: Hashable>(to point: CGPoint, among candidates: [(id: ID, frame: CGRect)]) -> ID? {
        candidates.min { a, b in distance(point, a.frame) < distance(point, b.frame) }?.id
    }
    private static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy + ((p.x - r.midX) * (p.x - r.midX) + (p.y - r.midY) * (p.y - r.midY)) * 0.001
    }

    /// The first item when nothing has focus yet: top-left first.
    static func first<ID: Hashable>(among candidates: [(id: ID, frame: CGRect)]) -> ID? {
        candidates.min { a, b in
            if abs(a.frame.minY - b.frame.minY) > 12 { return a.frame.minY < b.frame.minY }
            return a.frame.minX < b.frame.minX
        }?.id
    }
}
