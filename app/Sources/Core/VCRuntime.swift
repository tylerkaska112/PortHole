// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import CryptoKit
import zlib

// Microsoft's Visual C++ runtime for the x64 programs that games ship. The DLLs are Microsoft's, and are not part of this project or this
// app: the person downloads Microsoft's own installer from Microsoft (fixed address, fixed size, fixed SHA-256), and the 12 DLLs are taken
// out of it exactly as Microsoft made them. Each one is checked against a pinned SHA-256 again, so a changed or damaged file is never used.
// Same idea as `SteamRuntimeFiles`, which does this for Valve's client files.
enum VCRuntimeFiles {
    struct Entry: Sendable { let name: String; let bytes: Int; let sha256: String }

    /// Microsoft's "Visual C++ Redistributable" for x64 (14.x), by its content-addressed address (the SHA-256 is part of the path).
    static let installerURL = URL(string: "https://download.visualstudio.microsoft.com/download/pr/bd1c8d9d-ba95-4eee-bc6e-df1fcc876373/CC0FF0EB1DC3F5188AE6300FAEF32BF5BEEBA4BDD6E8E445A9184072096B713B/VC_redist.x64.exe")!
    static let installerBytes = 25_635_768
    static let installerSHA256 = "cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b"

    /// The files the app wants, with the hashes of Microsoft's originals in that installer.
    static let entries: [Entry] = [
        Entry(name: "concrt140.dll", bytes: 324208, sha256: "2405355f0a58067b258f8df33c327e3a3d716eaac5a3a5aebb757842d85bd376"),
        Entry(name: "msvcp140.dll", bytes: 557728, sha256: "0f885b509a685d2bbfa652fed26b5fb31d88fbdab0a978c641d1c7b8aa460aa9"),
        Entry(name: "msvcp140_1.dll", bytes: 35952, sha256: "bfad5aef4c63a669e3c140655cdfdf395b6c979b400a447bd5dcb65ed8826c3d"),
        Entry(name: "msvcp140_2.dll", bytes: 280200, sha256: "3ea06f0ee098b4823cb79599df3780e7f23cce52c19aac31d2a0d47efe33a5e9"),
        Entry(name: "msvcp140_atomic_wait.dll", bytes: 50304, sha256: "640b2aefced484d0368eea5bdd06addd0658a3a70a49256e560d6923b404a479"),
        Entry(name: "msvcp140_codecvt_ids.dll", bytes: 31872, sha256: "f2069a52880ec885ee7f0511186100eb7fada0411a2b4948fafea7735b878a18"),
        Entry(name: "vcamp140.dll", bytes: 418944, sha256: "52af68f35476bd03d7b97752b01bef358ffdda568d150057d6ce809f77c4f704"),
        Entry(name: "vccorlib140.dll", bytes: 352384, sha256: "19839407c3fdbc824e5bce189bf68ddf8097f12ec28b757797ffa0415c144ddd"),
        Entry(name: "vcomp140.dll", bytes: 193152, sha256: "55aba23cdcd6484fbb06f4155b8ca75adfce7a881f10afd0c49457165e677164"),
        Entry(name: "vcruntime140.dll", bytes: 124544, sha256: "d5e4d9a3e835fa679450145d6a7d94e36573a509317111904d9b3712c30d9066"),
        Entry(name: "vcruntime140_1.dll", bytes: 49792, sha256: "1f2d41c4aa5db0bc33ebf7b66d72943a817d7ce6cbe880502a9403823633093f"),
        Entry(name: "vcruntime140_threads.dll", bytes: 38528, sha256: "219915cf20822f34d5e7c1fdd4e21ae7f3396881096c51036225fb8f84b47afa"),
    ]

    enum Failure: LocalizedError, Equatable {
        case notTheExpectedInstaller
        case unreadable(String)
        case mismatch(String)
        var errorDescription: String? {
            switch self {
            case .notTheExpectedInstaller: return "What was downloaded is not the Microsoft installer this app expects, so it was not used. Try again."
            case .unreadable(let why): return "The Microsoft installer could not be unpacked (\(why))."
            case .mismatch(let name): return "\(name) does not match Microsoft's original, so it was not used."
            }
        }
    }

    // MARK: Checking

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Unpacks the installer and returns the 12 DLLs by name, each checked against its pinned hash. Throws if anything is off.
    static func extract(installer data: Data) throws -> [String: Data] {
        guard data.count == installerBytes, sha256Hex(data) == installerSHA256 else { throw Failure.notTheExpectedInstaller }
        // The installer is a small Windows program followed by two cabinets: the installer's own interface, then one holding every package.
        // The cabinet that is much bigger than the rest is the one with the packages.
        let candidates = Cabinet.find(in: data).sorted { $0.size > $1.size }
        guard let container = candidates.first, container.size > 1 << 20 else { throw Failure.unreadable("no package container") }

        var wanted: [String: Data]?
        try container.forEachFile { _, bytes in
            // Each package is itself a cabinet; the one with the x64 runtime lists its files as "<name>.dll_amd64".
            guard let inner = Cabinet(data: bytes, at: 0), inner.names.contains("vcruntime140.dll_amd64") else { return true }
            var out: [String: Data] = [:]
            try inner.forEachFile { name, content in
                if name.hasSuffix(".dll_amd64") { out[String(name.dropLast("_amd64".count))] = content }
                return true
            }
            wanted = out
            return false
        }
        guard let found = wanted else { throw Failure.unreadable("x64 runtime not found") }

        var result: [String: Data] = [:]
        for entry in entries {
            guard let content = found[entry.name] else { throw Failure.unreadable("\(entry.name) is missing") }
            guard content.count == entry.bytes, sha256Hex(content) == entry.sha256 else { throw Failure.mismatch(entry.name) }
            result[entry.name] = content
        }
        return result
    }
}

// MARK: - Microsoft cabinet files (one folder, MSZIP)

/// The part of the Microsoft cabinet format that the Visual C++ installer uses: one folder, compressed with MSZIP (deflate in 32 KB blocks,
/// each block continuing from the history of the one before). Anything else is refused, never guessed at.
struct Cabinet {
    let data: Data
    let base: Int
    let size: Int
    private let filesOffset: Int, fileCount: Int, folderOffset: Int, blockCount: Int, dataReserve: Int
    let names: [String]

    private static func u16(_ d: Data, _ p: Int) -> Int { Int(d[d.startIndex + p]) | Int(d[d.startIndex + p + 1]) << 8 }
    private static func u32(_ d: Data, _ p: Int) -> Int { u16(d, p) | u16(d, p + 2) << 16 }

    init?(data: Data, at base: Int) {
        let d = data
        guard base >= 0, base + 36 <= d.count, d[d.startIndex + base ..< d.startIndex + base + 4].elementsEqual("MSCF".utf8) else { return nil }
        let cbCabinet = Self.u32(d, base + 8), coffFiles = Self.u32(d, base + 16)
        let folders = Self.u16(d, base + 26), files = Self.u16(d, base + 28), flags = Self.u16(d, base + 30)
        guard Self.u16(d, base + 24) == 0x0103, folders == 1, files > 0, files <= 4096, flags & 3 == 0,
              cbCabinet >= 44, base + cbCabinet <= d.count, coffFiles < cbCabinet else { return nil }
        var p = base + 36, reserveHeader = 0, reserveFolder = 0, reserveData = 0
        if flags & 4 != 0 {
            guard p + 4 <= d.count else { return nil }
            reserveHeader = Self.u16(d, p); reserveFolder = Int(d[d.startIndex + p + 2]); reserveData = Int(d[d.startIndex + p + 3]); p += 4 + reserveHeader
        }
        guard p + 8 + reserveFolder <= base + cbCabinet else { return nil }
        let firstBlock = Self.u32(d, p), blocks = Self.u16(d, p + 4), compression = Self.u16(d, p + 6)
        guard compression & 0xf == 1, blocks > 0, firstBlock < cbCabinet else { return nil }
        self.data = d; self.base = base; self.size = cbCabinet
        self.filesOffset = base + coffFiles; self.fileCount = files; self.folderOffset = base + firstBlock
        self.blockCount = blocks; self.dataReserve = reserveData
        // The file table: size, offset in the unpacked folder, folder, date, time, attributes, then the name.
        var names: [String] = []
        var q = base + coffFiles
        for _ in 0..<files {
            guard q + 17 <= base + cbCabinet else { return nil }
            var e = q + 16
            while e < base + cbCabinet, d[d.startIndex + e] != 0 { e += 1 }
            guard e < base + cbCabinet, let name = String(data: d[d.startIndex + q + 16 ..< d.startIndex + e], encoding: .isoLatin1) else { return nil }
            names.append(name); q = e + 1
        }
        self.names = names
    }

    /// Cabinets that start somewhere in `data` (found by their signature, then checked in full).
    static func find(in data: Data) -> [Cabinet] {
        var found: [Cabinet] = []
        let signature = Data("MSCF".utf8)
        var from = data.startIndex
        while let range = data.range(of: signature, in: from ..< data.endIndex) {
            let offset = range.lowerBound - data.startIndex
            if let cabinet = Cabinet(data: data, at: offset) { found.append(cabinet); from = range.lowerBound + cabinet.size } else { from = range.upperBound }
        }
        return found
    }

    /// Unpacks the folder one block at a time and hands over each file as soon as all of its bytes exist. Return `false` from `body` to stop early.
    func forEachFile(_ body: (String, Data) throws -> Bool) throws {
        // The file table again, now with sizes and positions.
        var entries: [(name: String, size: Int, offset: Int)] = []
        var q = filesOffset
        for _ in 0..<fileCount {
            let size = Self.u32(data, q), offset = Self.u32(data, q + 4)
            var e = q + 16
            while data[data.startIndex + e] != 0 { e += 1 }
            let name = String(data: data[data.startIndex + q + 16 ..< data.startIndex + e], encoding: .isoLatin1) ?? ""
            entries.append((name, size, offset)); q = e + 1
        }
        var output = Data()
        var next = 0
        var p = folderOffset
        let limit = base + size
        for _ in 0..<blockCount {
            guard p + 8 + dataReserve <= limit else { throw VCRuntimeFiles.Failure.unreadable("cabinet is cut short") }
            let compressed = Self.u16(data, p + 4), uncompressed = Self.u16(data, p + 6)
            p += 8 + dataReserve
            guard compressed >= 2, uncompressed <= 32768, p + compressed <= limit,
                  data[data.startIndex + p] == 0x43, data[data.startIndex + p + 1] == 0x4B else { throw VCRuntimeFiles.Failure.unreadable("bad block") }
            let history = output.count >= 32768 ? output.suffix(32768) : output[...]
            let block = try Self.unpackBlock(data[data.startIndex + p + 2 ..< data.startIndex + p + compressed], expecting: uncompressed, history: Data(history))
            output.append(block)
            p += compressed
            while next < entries.count, entries[next].offset + entries[next].size <= output.count {
                let entry = entries[next]
                if try !body(entry.name, Data(output[entry.offset ..< entry.offset + entry.size])) { return }
                next += 1
            }
        }
        guard next == entries.count else { throw VCRuntimeFiles.Failure.unreadable("files run past the end of the cabinet") }
    }

    private static func unpackBlock(_ input: Data, expecting count: Int, history: Data) throws -> Data {
        var out = Data(count: count)
        var ok = false
        input.withUnsafeBytes { source in
            out.withUnsafeMutableBytes { destination in
                history.withUnsafeBytes { dictionary in
                    var stream = z_stream()
                    stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: UInt8.self).baseAddress)
                    stream.avail_in = UInt32(input.count)
                    stream.next_out = destination.bindMemory(to: UInt8.self).baseAddress
                    stream.avail_out = UInt32(count)
                    guard inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return }
                    defer { inflateEnd(&stream) }
                    if !history.isEmpty {
                        guard inflateSetDictionary(&stream, dictionary.bindMemory(to: UInt8.self).baseAddress, UInt32(history.count)) == Z_OK else { return }
                    }
                    ok = inflate(&stream, Z_FINISH) == Z_STREAM_END && Int(stream.total_out) == count
                }
            }
        }
        guard ok else { throw VCRuntimeFiles.Failure.unreadable("a block would not unpack") }
        return out
    }
}
