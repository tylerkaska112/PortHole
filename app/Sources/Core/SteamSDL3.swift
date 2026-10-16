// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import Compression
import CryptoKit

/// Steam's controller layer (Steam Input) for the 64-bit Steam client the Dock runs.
///
/// Valve's 64-bit code loads "SDL3.dll" by name for it. The Steam components Porthole installs contain only the 32-bit SDL3.dll, which a 64-bit process cannot load (status
/// c000007b, "Failed to load SDL3.dll" in every Steam run), so Steam Input never saw a controller. Games that take their pad from Steam Input (Portal, Portal 2) got none in any
/// controller mode. Valve's 64-bit client package has the matching 64-bit file. This is a download the person starts from the Steam page, like the Steam client itself: one file of
/// about 1.3 MB, asked of Valve's update server with a ranged request (not the 64 MB package it belongs to), checked against a pinned SHA-256 before anything is written. The 32-bit
/// file is kept as SDL3.x86.dll and can be put back. Nothing is downloaded unless the person asks.
enum SteamSDL3 {
    static let host = "client-update.akamai.steamstatic.com"
    private static let package = "bins_win64.zip.0ed643edc3bd395674066241d556cd970f4bdc19"
    /// SDL3.dll inside that package: its deflated bytes (from the zip's directory) and what they become.
    private static let firstByte = 1_189_083, lastByte = 2_473_377
    private static let size = 3_093_144
    private static let sha256 = "66db88c627480b1b15123c98fab459ae25905e1375a4737e87b0830928980151"
    private static let machineX64: UInt16 = 0x8664

    enum Failure: LocalizedError {
        case noSteam, activeSession, download, mismatch
        var errorDescription: String? {
            switch self {
            case .noSteam: "Download the Steam client first."
            case .activeSession: "Close the running game first."
            case .download: "Valve's server did not give the file. Try again."
            case .mismatch: "The file did not match what was expected, so it was not used."
            }
        }
    }

    private static var steamFolder: URL { AppModel.prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true) }
    private static var root: URL { steamFolder.appendingPathComponent("SDL3.dll") }
    private static var kept: URL { steamFolder.appendingPathComponent("SDL3.x86.dll") }

    /// 0x14c = 32-bit, 0x8664 = 64-bit, nil = not a readable PE file.
    static func machine(of file: URL) -> UInt16? {
        guard let h = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? h.close() }
        guard let head = try? h.read(upToCount: 0x400), head.count > 0x40, head[0] == 0x4d, head[1] == 0x5a else { return nil }
        let pe = Int(head[0x3c]) | Int(head[0x3d]) << 8
        guard pe + 6 <= head.count else { return nil }
        return UInt16(head[pe + 4]) | UInt16(head[pe + 5]) << 8
    }

    /// The Steam folder's SDL3.dll is the 64-bit one.
    static var installed: Bool { machine(of: root) == machineX64 }
    /// A Steam client is there to give a controller layer to.
    static var steamPresent: Bool { FileManager.default.fileExists(atPath: steamFolder.appendingPathComponent("steamclient64.dll").path) }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private final class Redirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            let url = request.url
            completionHandler(url?.scheme == "https" && url?.host == SteamSDL3.host && (url?.port == nil || url?.port == 443) ? request : nil)
        }
    }

    /// Downloads the 64-bit file, checks it, and makes it Steam's SDL3.dll.
    static func install(progress: @Sendable (String) async -> Void) async throws {
        guard steamPresent else { throw Failure.noSteam }
        guard wine_process_is_running() == 0, wineserver_is_running() == 0 else { throw Failure.activeSession }
        await progress("Downloading from Valve\u{2026}")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration, delegate: Redirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://\(host)/\(package)")!)
        request.setValue("bytes=\(firstByte)-\(lastByte)", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 206, http.url?.host == host, data.count == lastByte - firstByte + 1 else { throw Failure.download }
        await progress("Checking the file\u{2026}")
        // The zip stores the file deflated (raw deflate, which is what COMPRESSION_ZLIB reads).
        var out = [UInt8](repeating: 0, count: size)
        let produced = data.withUnsafeBytes { src in
            out.withUnsafeMutableBytes { dst in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        let file = Data(out)
        guard produced == size, digest(file) == sha256 else { throw Failure.mismatch }
        try Task.checkCancellation()
        guard wine_process_is_running() == 0, wineserver_is_running() == 0 else { throw Failure.activeSession }
        let fm = FileManager.default
        if fm.fileExists(atPath: root.path) {
            if !fm.fileExists(atPath: kept.path) { try fm.moveItem(at: root, to: kept) } else { try fm.removeItem(at: root) }
        }
        try file.write(to: root, options: .atomic)
        LogStore.shared.log("[steam-sdl3] Steam's SDL3.dll is now Valve's 64-bit one (hash checked); the 32-bit one is SDL3.x86.dll")
        await progress("Done.")
    }

    /// Puts the 32-bit file back.
    static func remove() throws {
        guard wine_process_is_running() == 0, wineserver_is_running() == 0 else { throw Failure.activeSession }
        let fm = FileManager.default
        guard fm.fileExists(atPath: kept.path) else { return }
        if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }
        try fm.moveItem(at: kept, to: root)
        LogStore.shared.log("[steam-sdl3] the 32-bit SDL3.dll is back")
    }
}
