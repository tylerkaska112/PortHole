// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Testing
import Foundation
@testable import LauncherCore

/// A local server that sends 24 MB in pieces with short pauses, so progress has to arrive in steps.
final class SlowServer: @unchecked Sendable {
    let port = Int.random(in: 41_000..<49_000)
    private let process = Process()

    init?() async {
        let script = """
        import http.server, sys, time
        class H(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                total = 24 * 1024 * 1024
                self.send_response(200); self.send_header('Content-Length', str(total)); self.end_headers()
                chunk = b'x' * (1024 * 1024)
                try:
                    for _ in range(24):
                        self.wfile.write(chunk); self.wfile.flush(); time.sleep(0.03)
                except (BrokenPipeError, ConnectionResetError):
                    pass
            def log_message(self, *a): pass
        http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
        """
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", script, String(port)]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            var probe = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
            probe.httpMethod = "HEAD"
            if (try? await URLSession.shared.data(for: probe)) != nil { return }
        }
        stop(); return nil
    }

    func stop() { if process.isRunning { process.terminate() } }
}

@Suite("Downloads report progress")
struct TransportProgressTests {
    final class Seen: @unchecked Sendable {
        private let lock = NSLock(); private var values: [Double] = []
        func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() }
        var all: [Double] { lock.lock(); defer { lock.unlock() }; return values }
    }

    @Test func aDownloadReportsGrowingProgressUntilItReachesOne() async throws {
        guard let server = await SlowServer() else { Issue.record("couldn't start the test server — is python3 installed?"); return }
        defer { server.stop() }
        let seen = Seen()
        let (file, response) = try await URLSessionTransport().download(URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/big.ipa")!)) { seen.add($0) }
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(response.statusCode == 200)
        #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) == 24 * 1024 * 1024)
        let values = seen.all
        #expect(values.count >= 5, "progress arrived in \(values.count) steps")
        #expect(values == values.sorted(), "progress never goes backwards")
        #expect(values.last == 1)
        #expect(values.first.map { $0 < 0.6 } == true, "the first report is early, not just the end")
    }

    @Test func cancellingStopsTheDownload() async throws {
        guard let server = await SlowServer() else { Issue.record("couldn't start the test server"); return }
        defer { server.stop() }
        let task = Task { try await URLSessionTransport().download(URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/big.ipa")!)) { _ in } }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        let result = await task.result
        if case .success = result { Issue.record("a cancelled download should not succeed") }
    }
}
