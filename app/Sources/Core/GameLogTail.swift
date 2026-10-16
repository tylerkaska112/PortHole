// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Copies what a Unity game writes to its own log (`AppData\LocalLow\<company>\<game>\Player.log`, `output_log.txt` in older ones) into Porthole's log while the game runs, as
/// `[game-log]` lines. A game that stops loading never ends, so a log read afterwards would never be there: this shows what the game itself said last (the scene it was
/// loading, the error it hit). Reads only what a file gained since the last look (at most 64 KB at a time, 1,500 lines a session). `env.PORTHOLE_GAME_LOG = 0` switches it off.
@MainActor
enum GameLogTail {
    private static var timer: DispatchSourceTimer?
    private static var state = State()
    private static let queue = DispatchQueue(label: "porthole.gamelog", qos: .utility)

    private final class State: @unchecked Sendable {
        var started = Date(), offsets: [String: UInt64] = [:], lines = 0, announced = Set<String>()
    }

    static func begin() {
        guard timer == nil, EngineOptions.value("env.PORTHOLE_GAME_LOG") != "0" else { return }
        let st = State()
        state = st
        let root = AppModel.driveC.appendingPathComponent("users")
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { Self.tick(st, root: root) }
        timer = t
        t.resume()
    }

    static func end() {
        timer?.cancel(); timer = nil
        let st = state
        queue.async { Self.tick(st, root: AppModel.driveC.appendingPathComponent("users")) }   // the last words
    }

    nonisolated private static func tick(_ st: State, root: URL) {
        guard st.lines < 1500 else { return }
        let fm = FileManager.default
        guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        var found: [URL] = []
        for case let url as URL in walk {
            if url.pathComponents.count - root.pathComponents.count > 7 { walk.skipDescendants(); continue }
            let n = url.lastPathComponent
            guard n == "Player.log" || n == "output_log.txt" else { continue }
            if let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d >= st.started.addingTimeInterval(-2) { found.append(url) }
        }
        for url in found {
            guard let h = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? h.close() }
            let size = (try? h.seekToEnd()) ?? 0
            var off = st.offsets[url.path] ?? 0
            if size < off { off = 0 }
            if size - off > 65536 { off = size - 65536 }   // far behind: keep the newest part
            guard size > off, (try? h.seek(toOffset: off)) != nil, let data = try? h.read(upToCount: Int(size - off)) else { continue }
            st.offsets[url.path] = size
            let text = String(decoding: data, as: UTF8.self)
            var out: [String] = []
            if st.announced.insert(url.path).inserted { out.append("[game-log] following \(url.lastPathComponent)") }
            for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
                st.lines += 1
                if st.lines > 1500 { out.append("[game-log] stopping: 1,500 lines this session"); break }
                out.append("[game-log] " + String(raw.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if !out.isEmpty { Task { @MainActor in out.forEach { LogStore.shared.log($0) } } }
        }
    }
}
