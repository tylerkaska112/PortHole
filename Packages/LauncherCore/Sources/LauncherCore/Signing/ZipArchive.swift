// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import Compression

/// One file (or folder) inside a zip.
public struct ZipEntry: Equatable, Sendable {
    public var name: String
    /// The file's contents. Changing them drops `packed`, so the entry is checksummed and compressed afresh when the archive is written.
    public var data: Data { didSet { packed = nil } }
    /// Unix permission bits (`0o755`); the executable bit matters inside an IPA.
    public var mode: UInt16
    var dosTime: UInt16
    var dosDate: UInt16
    /// The entry as the archive it was read from stored it. While `data` is untouched it is written back as it is: most of an app's files are not changed by
    /// signing, and unpacking, checksumming and packing hundreds of megabytes again was most of the time signing took.
    var packed: Packed?

    struct Packed: Sendable {
        var method: UInt16
        var payload: Data
        var crc: UInt32
    }

    public static func == (a: ZipEntry, b: ZipEntry) -> Bool {
        a.name == b.name && a.data == b.data && a.mode == b.mode && a.dosTime == b.dosTime && a.dosDate == b.dosDate
    }

    public var isDirectory: Bool { name.hasSuffix("/") }
    public var isSymlink: Bool { mode & 0o170000 == 0o120000 }

    public init(name: String, data: Data = Data(), mode: UInt16? = nil, date: Date = Date()) {
        self.name = name
        self.data = data
        self.mode = mode ?? (name.hasSuffix("/") ? 0o40755 : 0o100644)
        (dosTime, dosDate) = Self.dos(date)
    }

    static func dos(_ date: Date) -> (UInt16, UInt16) {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: date)
        let year = max(1980, parts.year ?? 1980)
        let time = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        let day = UInt16((year - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
        return (time, day)
    }
}

public enum ZipError: Error, LocalizedError, Equatable {
    case notAZip
    case corrupt(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .notAZip: "That file isn't a valid IPA (zip) archive."
        case .corrupt(let detail): "The IPA is damaged (\(detail))."
        case .unsupported(let detail): "The IPA uses something unsupported (\(detail))."
        }
    }
}

/// Reads and writes zip files (what an IPA is), all in memory. Deflate comes from the system's Compression framework.
public enum ZipArchive {
    // MARK: Reading

    public static func read(_ data: Data) throws -> [ZipEntry] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ZipError.notAZip }
        // End-of-central-directory record: scan backwards (a comment may follow it).
        var eocd = -1
        var index = bytes.count - 22
        while index >= max(0, bytes.count - 22 - 65535) {
            if u32(bytes, index) == 0x06054b50 { eocd = index; break }
            index -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let count = Int(u16(bytes, eocd + 10))
        var offset = Int(u32(bytes, eocd + 16))
        if count == 0xffff || offset == 0xffff_ffff { throw ZipError.unsupported("zip64") }

        // The central directory first (cheap), then every entry is unpacked at once on all cores.
        struct Located { let name: String, method: UInt16, start: Int, compressed: Int, size: Int, crc: UInt32, time: UInt16, date: UInt16, mode: UInt16 }
        var located: [Located] = []
        located.reserveCapacity(count)
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, u32(bytes, offset) == 0x02014b50 else { throw ZipError.corrupt("central directory") }
            let method = u16(bytes, offset + 10)
            let time = u16(bytes, offset + 12), date = u16(bytes, offset + 14)
            let crc = u32(bytes, offset + 16)
            let compressed = Int(u32(bytes, offset + 20)), size = Int(u32(bytes, offset + 24))
            let nameLength = Int(u16(bytes, offset + 28)), extraLength = Int(u16(bytes, offset + 30)), commentLength = Int(u16(bytes, offset + 32))
            let external = u32(bytes, offset + 38)
            let local = Int(u32(bytes, offset + 42))
            guard offset + 46 + nameLength <= bytes.count else { throw ZipError.corrupt("entry name") }
            let name = String(decoding: bytes[offset + 46..<offset + 46 + nameLength], as: UTF8.self)
            offset += 46 + nameLength + extraLength + commentLength

            guard local + 30 <= bytes.count, u32(bytes, local) == 0x04034b50 else { throw ZipError.corrupt("local header of \(name)") }
            let start = local + 30 + Int(u16(bytes, local + 26)) + Int(u16(bytes, local + 28))
            guard start + compressed <= bytes.count else { throw ZipError.corrupt("data of \(name)") }
            guard method == 0 || method == 8 else { throw ZipError.unsupported("compression method \(method) in \(name)") }
            var mode = UInt16(truncatingIfNeeded: external >> 16)
            if mode == 0 { mode = name.hasSuffix("/") ? 0o40755 : 0o100644 }
            located.append(Located(name: name, method: method, start: start, compressed: compressed, size: size, crc: crc, time: time, date: date, mode: mode))
        }

        let results = UnsafeMutablePointer<ZipEntry?>.allocate(capacity: located.count)
        results.initialize(repeating: nil, count: located.count)
        defer { results.deinitialize(count: located.count); results.deallocate() }
        let sink = ResultSink(results)
        let failure = FirstError()
        bytes.withUnsafeBufferPointer { source in
            nonisolated(unsafe) let base = source
            DispatchQueue.concurrentPerform(iterations: located.count) { i in
                if failure.value != nil { return }
                let item = located[i]
                let stored = Data(base[item.start..<item.start + item.compressed])
                do {
                    let content = item.method == 0 ? stored : try inflate(stored, expected: item.size, name: item.name)
                    var entry = ZipEntry(name: item.name, data: content, mode: item.mode)
                    entry.dosTime = item.time
                    entry.dosDate = item.date
                    entry.packed = ZipEntry.Packed(method: item.method, payload: stored, crc: item.crc)
                    sink.store(entry, at: i)
                } catch { failure.set(error) }
            }
        }
        if let error = failure.value { throw error }
        return (0..<located.count).map { results[$0]! }
    }

    /// One slot per entry, each written by exactly one task.
    private struct ResultSink: @unchecked Sendable {
        let pointer: UnsafeMutablePointer<ZipEntry?>
        init(_ pointer: UnsafeMutablePointer<ZipEntry?>) { self.pointer = pointer }
        func store(_ entry: ZipEntry, at index: Int) { pointer[index] = entry }
    }

    private final class FirstError: @unchecked Sendable {
        private let lock = NSLock()
        private var error: Error?
        func set(_ new: Error) { lock.lock(); if error == nil { error = new }; lock.unlock() }
        var value: Error? { lock.lock(); defer { lock.unlock() }; return error }
    }

    private static func inflate(_ data: Data, expected: Int, name: String) throws -> Data {
        if expected == 0 { return Data() }
        var output = [UInt8](repeating: 0, count: expected)
        let written = data.withUnsafeBytes { source -> Int in
            output.withUnsafeMutableBytes { destination in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, expected,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expected else { throw ZipError.corrupt("couldn't unpack \(name)") }
        return Data(output)
    }

    // MARK: Writing

    public static func write(_ entries: [ZipEntry]) throws -> Data {
        // What goes into the file for each entry: untouched ones as they were read; the others checksummed and compressed, all of them at once on all cores.
        struct Out: Sendable { var method: UInt16; var payload: Data; var crc: UInt32 }
        let outs = UnsafeMutablePointer<Out?>.allocate(capacity: entries.count)
        outs.initialize(repeating: nil, count: entries.count)
        defer { outs.deinitialize(count: entries.count); outs.deallocate() }
        let todo = entries.indices.filter { entries[$0].packed == nil }
        nonisolated(unsafe) let slots = outs
        DispatchQueue.concurrentPerform(iterations: todo.count) { n in
            let i = todo[n]
            let entry = entries[i]
            let crc = CRC32.checksum(entry.data)
            var method: UInt16 = 0
            var payload = entry.data
            if !entry.isDirectory, !entry.isSymlink, entry.data.count > 64, let packed = deflate(entry.data), packed.count < entry.data.count {
                method = 8
                payload = packed
            }
            slots[i] = Out(method: method, payload: payload, crc: crc)
        }

        var out = Data()
        var central = Data()
        for (i, entry) in entries.enumerated() {
            let name = Data(entry.name.utf8)
            let chosen: Out
            if let packed = entry.packed { chosen = Out(method: packed.method, payload: packed.payload, crc: packed.crc) } else { chosen = outs[i]! }
            let method = chosen.method, payload = chosen.payload, crc = chosen.crc
            guard out.count < 0xffff_ffff, payload.count < 0xffff_ffff else { throw ZipError.unsupported("archives over 4 GB") }
            let offset = UInt32(out.count)

            var local = Data()
            local.le32(0x04034b50); local.le16(20); local.le16(0x0800); local.le16(method)
            local.le16(entry.dosTime); local.le16(entry.dosDate)
            local.le32(crc); local.le32(UInt32(payload.count)); local.le32(UInt32(entry.data.count))
            local.le16(UInt16(name.count)); local.le16(0)
            out.append(local); out.append(name); out.append(payload)

            central.le32(0x02014b50); central.le16(0x031e); central.le16(20); central.le16(0x0800); central.le16(method)
            central.le16(entry.dosTime); central.le16(entry.dosDate)
            central.le32(crc); central.le32(UInt32(payload.count)); central.le32(UInt32(entry.data.count))
            central.le16(UInt16(name.count)); central.le16(0); central.le16(0); central.le16(0); central.le16(0)
            central.le32(UInt32(entry.mode) << 16); central.le32(offset)
            central.append(name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.le32(0x06054b50); out.le16(0); out.le16(0)
        out.le16(UInt16(entries.count)); out.le16(UInt16(entries.count))
        out.le32(UInt32(central.count)); out.le32(centralOffset); out.le16(0)
        return out
    }

    private static func deflate(_ data: Data) -> Data? {
        let capacity = data.count + data.count / 16 + 1024
        var output = [UInt8](repeating: 0, count: capacity)
        let written = data.withUnsafeBytes { source -> Int in
            output.withUnsafeMutableBytes { destination in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        return written > 0 ? Data(output[0..<written]) : nil
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 { UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24 }
}

enum CRC32 {
    /// Eight tables, so eight bytes are folded in per step (the plain one-byte-at-a-time loop over a `Data` was most of the time spent packing an IPA).
    private static let tables: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 8 * 256)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 { c = c & 1 == 1 ? 0xedb88320 ^ (c >> 1) : c >> 1 }
            t[n] = c
        }
        for n in 0..<256 {
            for k in 1..<8 { t[k * 256 + n] = (t[(k - 1) * 256 + n] >> 8) ^ t[Int(t[(k - 1) * 256 + n] & 0xff)] }
        }
        return t
    }()

    static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { raw -> UInt32 in
            tables.withUnsafeBufferPointer { t -> UInt32 in
                var crc: UInt32 = 0xffff_ffff
                var i = 0
                let n = raw.count
                while i + 8 <= n {
                    let lo = raw.loadUnaligned(fromByteOffset: i, as: UInt32.self).littleEndian ^ crc
                    let hi = raw.loadUnaligned(fromByteOffset: i + 4, as: UInt32.self).littleEndian
                    crc = t[7 * 256 + Int(lo & 0xff)] ^ t[6 * 256 + Int((lo >> 8) & 0xff)] ^ t[5 * 256 + Int((lo >> 16) & 0xff)] ^ t[4 * 256 + Int(lo >> 24)]
                      ^ t[3 * 256 + Int(hi & 0xff)] ^ t[2 * 256 + Int((hi >> 8) & 0xff)] ^ t[1 * 256 + Int((hi >> 16) & 0xff)] ^ t[Int(hi >> 24)]
                    i += 8
                }
                while i < n {
                    crc = t[Int((crc ^ UInt32(raw[i])) & 0xff)] ^ (crc >> 8)
                    i += 1
                }
                return crc ^ 0xffff_ffff
            }
        }
    }
}

extension Data {
    mutating func le16(_ value: UInt16) { append(UInt8(value & 0xff)); append(UInt8(value >> 8)) }
    mutating func le32(_ value: UInt32) { for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((value >> UInt32(shift)) & 0xff)) } }
    mutating func be32(_ value: UInt32) { for shift in stride(from: 24, through: 0, by: -8) { append(UInt8((value >> UInt32(shift)) & 0xff)) } }
    mutating func be64(_ value: UInt64) { for shift in stride(from: 56, through: 0, by: -8) { append(UInt8((value >> UInt64(shift)) & 0xff)) } }
}
