// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Decides how many chunk downloads to keep in flight: probes upwards while the rate keeps rising, backs off when it stops, holds while it is
/// steady and tries again now and then. Pure arithmetic on the bytes counter, so it can be tested without a network.
struct ConcurrencyController {
    private(set) var target: Int
    private let floor: Int
    private let ceiling: Int
    private let step = 6
    private var windowStart: Date?
    private var windowBytes: UInt64 = 0
    private var lastRate = 0.0
    private var settledRate = 0.0
    private var probing = false
    private var held = 0

    init(start: Int, floor: Int, ceiling: Int) { target = min(max(start, floor), ceiling); self.floor = floor; self.ceiling = ceiling }

    private mutating func probe(settleAt rate: Double) {
        if target + step <= ceiling { target += step; probing = true }
        else { probing = false; held = 0; settledRate = rate }
    }

    mutating func observe(totalBytes: UInt64, now: Date) {
        guard let start = windowStart else { windowStart = now; windowBytes = totalBytes; return }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= 3 else { return }
        let rate = Double(totalBytes &- windowBytes) / elapsed
        windowStart = now; windowBytes = totalBytes
        defer { lastRate = rate }
        if lastRate == 0 { probe(settleAt: rate); return }
        if probing {
            if rate > lastRate * 1.05 { probe(settleAt: rate) }
            else { target = max(floor, target - step); probing = false; held = 0; settledRate = max(rate, lastRate) }
        } else {
            held += 1
            if rate < settledRate * 0.75 { target = max(floor, target - 2); settledRate = rate; held = 0 }
            else if held >= 6 { settledRate = max(settledRate * 0.9, rate); probe(settleAt: rate) }
        }
    }
}
