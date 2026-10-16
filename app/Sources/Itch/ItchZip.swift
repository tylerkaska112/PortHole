// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
//
// Unpacks a .zip onto disk without holding it in memory: reads the central directory (ZIP64 included), then inflates each entry in small steps with a
// CRC-32 check. Only stored and deflated entries are supported (what itch.io builds use); encrypted or other-method entries stop with a clear message.
// Every path is checked so nothing can land outside the destination folder.

import Foundation
import zlib

enum ItchZipError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct ItchZipEntry {
    let path: String           // forward slashes, validated
    let isDirectory: Bool
    let method: UInt16
    let crc: UInt32
    let compressedSize: UInt64
    let size: UInt64
    let headerOffset: UInt64
    let encrypted: Bool
    let isSymlink: Bool
}

enum ItchZip {
    /// The entries of a zip, in the order of its central directory.
    static func entries(of url: URL) throws -> [ItchZipEntry] {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let length = try file.seekToEnd()
        guard length >= 22 else { throw ItchZipError.invalid("This is not a zip file.") }

        // The end-of-central-directory record is in the last 64 KB + 22 bytes.
        let tailSize = min(length, 65_557 + 22)
        try file.seek(toOffset: length - tailSize)
        let tail = try file.read(upToCount: Int(tailSize)) ?? Data()
        var eocd = -1
        var i = tail.count - 22
        while i >= 0 {
            if tail[i] == 0x50, tail[i + 1] == 0x4b, tail[i + 2] == 0x05, tail[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ItchZipError.invalid("This is not a zip file.") }
        var count = UInt64(le16(tail, eocd + 10))
        var directorySize = UInt64(le32(tail, eocd + 12))
        var directoryOffset = UInt64(le32(tail, eocd + 16))

        if count == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            // ZIP64: the locator sits just before the EOCD, and points at the ZIP64 end record.
            let locator = eocd - 20
            guard locator >= 0, le32(tail, locator) == 0x0706_4b50 else { throw ItchZipError.invalid("This zip file is damaged (no ZIP64 locator).") }
            let recordOffset = le64(tail, locator + 8)
            try file.seek(toOffset: recordOffset)
            let record = try file.read(upToCount: 56) ?? Data()
            guard record.count >= 56, le32(record, 0) == 0x0606_4b50 else { throw ItchZipError.invalid("This zip file is damaged (no ZIP64 record).") }
            count = le64(record, 32)
            directorySize = le64(record, 40)
            directoryOffset = le64(record, 48)
        }
        guard directorySize < 512 * 1024 * 1024, directoryOffset + directorySize <= length, count <= 2_000_000 else {
            throw ItchZipError.invalid("This zip file is damaged (bad directory).")
        }
        try file.seek(toOffset: directoryOffset)
        let directory = try file.read(upToCount: Int(directorySize)) ?? Data()
        guard directory.count == Int(directorySize) else { throw ItchZipError.invalid("This zip file is damaged (short directory).") }

        var result: [ItchZipEntry] = []
        result.reserveCapacity(Int(count))
        var p = 0
        for _ in 0 ..< count {
            guard p + 46 <= directory.count, le32(directory, p) == 0x0201_4b50 else { throw ItchZipError.invalid("This zip file is damaged (bad entry).") }
            let flags = le16(directory, p + 8)
            let method = le16(directory, p + 10)
            let crc = le32(directory, p + 16)
            var compressed = UInt64(le32(directory, p + 20))
            var size = UInt64(le32(directory, p + 24))
            let nameLength = Int(le16(directory, p + 28)), extraLength = Int(le16(directory, p + 30)), commentLength = Int(le16(directory, p + 32))
            let attributes = le32(directory, p + 38)
            var offset = UInt64(le32(directory, p + 42))
            guard p + 46 + nameLength + extraLength + commentLength <= directory.count else { throw ItchZipError.invalid("This zip file is damaged (entry overruns).") }
            let nameBytes = directory.subdata(in: p + 46 ..< p + 46 + nameLength)
            // ZIP64 extra field: the 64-bit values replace the ones that were 0xFFFFFFFF, in this order.
            var q = p + 46 + nameLength
            let extraEnd = q + extraLength
            while q + 4 <= extraEnd {
                let id = le16(directory, q), len = Int(le16(directory, q + 2))
                if id == 0x0001 {
                    var r = q + 4
                    if size == 0xFFFF_FFFF, r + 8 <= extraEnd { size = le64(directory, r); r += 8 }
                    if compressed == 0xFFFF_FFFF, r + 8 <= extraEnd { compressed = le64(directory, r); r += 8 }
                    if offset == 0xFFFF_FFFF, r + 8 <= extraEnd { offset = le64(directory, r); r += 8 }
                }
                q += 4 + len
            }
            p += 46 + nameLength + extraLength + commentLength

            let utf8 = flags & 0x0800 != 0
            let raw = (utf8 ? String(data: nameBytes, encoding: .utf8) : nil) ?? String(data: nameBytes, encoding: .isoLatin1) ?? ""
            var name = raw.replacingOccurrences(of: "\\", with: "/")
            let isDirectory = name.hasSuffix("/")
            while name.hasSuffix("/") { name.removeLast() }
            if name.isEmpty || name.hasPrefix("__MACOSX/") { continue }
            guard let safe = GogContent.safePath(name) else { throw ItchZipError.invalid("This zip holds an unsafe path (\(name.prefix(40))).") }
            let unixMode = UInt16(truncatingIfNeeded: attributes >> 16)
            result.append(ItchZipEntry(path: safe, isDirectory: isDirectory, method: method, crc: crc, compressedSize: compressed, size: size,
                                       headerOffset: offset, encrypted: flags & 1 != 0, isSymlink: (unixMode & 0o170000) == 0o120000))
        }
        return result
    }

    /// Writes the entries under `root`. A single wrapping folder is left out of the paths when `stripCommonFolder` is set. `progress` gets bytes written.
    static func extract(_ url: URL, to root: URL, stripCommonFolder: Bool, progress: @escaping @Sendable (UInt64) -> Void) throws {
        let all = try entries(of: url)
        guard !all.isEmpty else { throw ItchZipError.invalid("The zip file is empty.") }
        var prefix = ""
        if stripCommonFolder {
            let firsts = Set(all.map { $0.path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? "" })
            let everyPathHasFolder = all.allSatisfy { $0.path.contains("/") || $0.isDirectory }
            if firsts.count == 1, let only = firsts.first, !only.isEmpty, everyPathHasFolder { prefix = only + "/" }
        }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var written: UInt64 = 0
        for entry in all {
            try Task.checkCancellation()
            var relative = entry.path
            if !prefix.isEmpty { guard relative.hasPrefix(prefix) else { continue }; relative = String(relative.dropFirst(prefix.count)) }
            if relative.isEmpty { continue }
            let target = root.appendingPathComponent(relative)
            if entry.isDirectory { try fm.createDirectory(at: target, withIntermediateDirectories: true); continue }
            if entry.isSymlink { continue }
            guard !entry.encrypted else { throw ItchZipError.invalid("This zip file is password-protected.") }
            guard entry.method == 0 || entry.method == 8 else {
                throw ItchZipError.invalid("This zip uses a compression method Porthole cannot unpack yet (method \(entry.method)).")
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

            // Local header: the data starts after its own name and extra field (their lengths can differ from the central directory's).
            try file.seek(toOffset: entry.headerOffset)
            let local = try file.read(upToCount: 30) ?? Data()
            guard local.count == 30, le32(local, 0) == 0x0403_4b50 else { throw ItchZipError.invalid("This zip file is damaged (bad local header).") }
            let dataStart = entry.headerOffset + 30 + UInt64(le16(local, 26)) + UInt64(le16(local, 28))
            try file.seek(toOffset: dataStart)

            fm.createFile(atPath: target.path, contents: nil)
            let out = try FileHandle(forWritingTo: target)
            do {
                try copy(entry, from: file, to: out) { delta in written += delta; progress(written) }
                try out.synchronize(); try out.close()
            } catch {
                try? out.close(); try? fm.removeItem(at: target)
                throw error
            }
        }
    }

    private static func copy(_ entry: ItchZipEntry, from file: FileHandle, to out: FileHandle, progress: (UInt64) -> Void) throws {
        if entry.size == 0 { return }
        var remaining = entry.compressedSize
        var crc = crc32(0, nil, 0)
        var produced: UInt64 = 0

        func emit(_ piece: Data) throws {
            try out.write(contentsOf: piece)
            piece.withUnsafeBytes { raw in crc = crc32(crc, raw.bindMemory(to: Bytef.self).baseAddress, uInt(piece.count)) }
            produced += UInt64(piece.count)
            progress(UInt64(piece.count))
        }

        if entry.method == 0 {
            while remaining > 0 {
                try Task.checkCancellation()
                let want = Int(min(remaining, 256 * 1024))
                let chunk = try file.read(upToCount: want) ?? Data()
                guard chunk.count == want else { throw ItchZipError.invalid("This zip file is damaged (short data).") }
                remaining -= UInt64(want)
                try emit(chunk)
            }
        } else {
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw ItchZipError.invalid("zlib could not start.") }
            defer { inflateEnd(&stream) }
            var buffer = [UInt8](repeating: 0, count: 256 * 1024)
            var ended = false
            while remaining > 0, !ended {
                try Task.checkCancellation()
                let want = Int(min(remaining, 256 * 1024))
                let chunk = try file.read(upToCount: want) ?? Data()
                guard chunk.count == want else { throw ItchZipError.invalid("This zip file is damaged (short data).") }
                remaining -= UInt64(want)
                try chunk.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    guard let base = raw.bindMemory(to: Bytef.self).baseAddress else { return }
                    stream.next_in = UnsafeMutablePointer(mutating: base)
                    stream.avail_in = uInt(chunk.count)
                    var status: Int32 = Z_OK
                    repeat {
                        let made: Int = buffer.withUnsafeMutableBufferPointer { out in
                            stream.next_out = out.baseAddress
                            stream.avail_out = uInt(out.count)
                            status = inflate(&stream, Z_NO_FLUSH)
                            return out.count - Int(stream.avail_out)
                        }
                        if made > 0 { try emit(Data(buffer[0 ..< made])) }
                        if status == Z_STREAM_END { ended = true; break }
                        if status != Z_OK && status != Z_BUF_ERROR { throw ItchZipError.invalid("A file in this zip is damaged.") }
                    } while stream.avail_in > 0 || stream.avail_out == 0
                }
            }
            guard ended else { throw ItchZipError.invalid("A file in this zip ended early.") }
        }
        guard produced == entry.size else { throw ItchZipError.invalid("A file in this zip has the wrong size.") }
        guard UInt32(truncatingIfNeeded: crc) == entry.crc else { throw ItchZipError.invalid("A file in this zip failed its checksum.") }
    }

    // MARK: Little-endian reads

    private static func le16(_ d: Data, _ o: Int) -> UInt16 { UInt16(d[d.startIndex + o]) | UInt16(d[d.startIndex + o + 1]) << 8 }
    private static func le32(_ d: Data, _ o: Int) -> UInt32 { UInt32(le16(d, o)) | UInt32(le16(d, o + 2)) << 16 }
    private static func le64(_ d: Data, _ o: Int) -> UInt64 { UInt64(le32(d, o)) | UInt64(le32(d, o + 4)) << 32 }
}
