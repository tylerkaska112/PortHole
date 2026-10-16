// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Bytes that arrived, counted by the download tasks and read by the window logic.
final class TransferCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: UInt64 = 0
    func add(_ n: Int) { lock.lock(); bytes &+= UInt64(n); lock.unlock() }
    var value: UInt64 { lock.lock(); defer { lock.unlock() }; return bytes }
}

/// Keeps downloads running AHEAD of whoever consumes them: pieces (chunks, file segments) are named in the order the consumer will need them, a sliding window of
/// them is in flight (the number adapts to the connection, see ConcurrencyController; a byte budget bounds the memory), and `take` hands each one over when it is needed.
/// Pieces are fetched and decoded off the caller's actor, so downloads and decompression run in parallel. Not thread-safe: one consumer calls it, in order.
final class ChunkWindow<Key: Hashable & Sendable> {
    private let order: [Key]
    private let weight: (Key) -> Int
    private let budget: Int
    private let fetch: @Sendable (Key) async throws -> (Data, Int)   // the piece's data and the bytes it took on the wire
    private let counter = TransferCounter()
    private var controller: ConcurrencyController
    private var inflight: [Key: Task<(Data, Int), Error>] = [:]
    private var ready: [Key: Data] = [:]
    private var kept: [Key: Data] = [:], keptOrder: [Key] = []   // handed over already; a few are kept in case the same piece is asked for again
    private var next = 0, held = 0
    private(set) var wireBytes: UInt64 = 0

    init(order: [Key], weight: @escaping (Key) -> Int, budget: Int = 96 * 1024 * 1024, start: Int = 12, floor: Int = 6, ceiling: Int = 48,
         fetch: @escaping @Sendable (Key) async throws -> (Data, Int)) {
        self.order = order; self.weight = weight; self.budget = budget; self.fetch = fetch
        controller = ConcurrencyController(start: start, floor: floor, ceiling: ceiling)
    }

    deinit { for task in inflight.values { task.cancel() } }

    func cancel() { for task in inflight.values { task.cancel() }; inflight = [:] }

    private func begin(_ key: Key) {
        held += weight(key)
        let fetch = self.fetch, counter = self.counter
        inflight[key] = Task.detached(priority: .userInitiated) {
            var lastError: Error?
            for attempt in 0..<4 {
                try Task.checkCancellation()
                do {
                    let (data, wire) = try await fetch(key)
                    counter.add(wire)
                    return (data, wire)
                } catch {
                    if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { throw CancellationError() }
                    lastError = error
                    try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 500_000_000)
                }
            }
            throw lastError ?? URLError(.unknown)
        }
    }

    private func pump() {
        controller.observe(totalBytes: counter.value, now: Date())
        while next < order.count, inflight.count < controller.target, held + weight(order[next]) <= budget {
            let key = order[next]; next += 1
            if inflight[key] == nil, ready[key] == nil { begin(key) }
        }
    }

    /// The piece, waiting for it if it is still coming. Throws what the fetch threw after its retries.
    func take(_ key: Key) async throws -> Data {
        if let again = kept[key] { pump(); return again }
        pump()
        if ready[key] == nil {
            if inflight[key] == nil { begin(key) }   // not in the plan (or dropped from the small cache): fetch it now
            let task = inflight[key]!
            let (data, wire) = try await task.value
            inflight[key] = nil; ready[key] = data; wireBytes += UInt64(wire)
        }
        let data = ready.removeValue(forKey: key)!
        held -= weight(key)
        kept[key] = data; keptOrder.removeAll { $0 == key }; keptOrder.append(key)
        while kept.values.reduce(0, { $0 + $1.count }) > 8 * 1024 * 1024, let oldest = keptOrder.first { kept.removeValue(forKey: oldest); keptOrder.removeFirst() }
        pump()
        return data
    }
}
