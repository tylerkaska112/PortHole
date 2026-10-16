// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Decides, while a game runs, whether the physical controller should reach it as an Xbox pad or as keyboard and mouse.
///
/// A game that reads XInput (or the HID pad) asks for the controller over and over, even with none connected: the engine counts those reads. A game that never asks has no
/// controller support, and an Xbox pad it never looks at does nothing, so after a grace period the pad is turned into keys and mouse. If the game starts reading later (a long
/// load, a menu that enables it) the pad goes back to being an Xbox pad at once. Nothing here applies when the player chose a mode for the game.
struct PadAuto {
    enum Decision: Equatable { case none, useKeys, useXInput }

    /// How long a running game gets to start reading the controller before the keyboard-and-mouse mode takes over.
    var grace: TimeInterval = 25
    private(set) var usingKeys = false
    private var startedAt: TimeInterval = 0
    private var baseline: UInt64 = 0

    /// `preferKeys`: the last run of this game never read the controller, so start in keyboard-and-mouse mode and let the reads switch it back.
    mutating func begin(now: TimeInterval, reads: UInt64, preferKeys: Bool) {
        startedAt = now; baseline = reads; usingKeys = preferKeys
    }

    mutating func update(now: TimeInterval, reads: UInt64, padConnected: Bool) -> Decision {
        if usingKeys {
            guard reads > baseline else { return .none }
            usingKeys = false; baseline = reads; startedAt = .infinity      // it reads the controller: it is not switched again this run
            return .useXInput
        }
        if reads > baseline { baseline = reads; startedAt = .infinity; return .none }      // the game reads the controller: it is fine as it is
        guard startedAt.isFinite, padConnected, now - startedAt >= grace else { return .none }
        usingKeys = true; baseline = reads
        return .useKeys
    }

    /// Whether the game has been seen reading the controller during this run.
    var gameReads: Bool { !startedAt.isFinite }
}
