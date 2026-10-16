// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
//
// Save backups: a game's progress lives in the Wine prefix (C:\\users\\...), which a prefix reset or a reinstall takes with it. A backup is one zip of every
// Windows user's Documents, Saved Games and AppData (caches and Valve's client files left out), to keep in Files or iCloud Drive; a restore puts the files back.
// The zip reading and writing and the folder rules are Madeira's (SavesAndShortcuts.swift, GPL-3.0-or-later with the Madeira Converter Exception),
// adapted to Porthole's folders and error type.
import Foundation
import Compression
import zlib

struct SaveError: LocalizedError {
    let text: String
    var errorDescription: String? { text }
    static func message(_ text: String) -> SaveError { SaveError(text: text) }
}

// MARK: - Zip writing (stored)

/// Uncompressed zip (saves are small, and many are compressed already). No
/// zip64: the backup stops before 3.5 GB or 65,535 files.
final class SaveZipWriter {
    static let maxEntries = 0xFFFF
    private let handle: FileHandle
    private var central = Data()
    private(set) var count = 0
    private(set) var offset: UInt64 = 0

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    private static func le16(_ v: Int) -> Data { var x = UInt16(truncatingIfNeeded: v).littleEndian; return Data(bytes: &x, count: 2) }
    private static func le32(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }

    func add(name: String, data: Data) throws {
        let n = Data(name.utf8)
        let crc = data.withUnsafeBytes { raw -> UInt32 in
            UInt32(crc32(0, raw.bindMemory(to: Bytef.self).baseAddress, uInt(raw.count)))
        }
        let size = UInt32(data.count)
        // Version 2.0, UTF-8 names (bit 11), stored, 1980-01-01 00:00.
        var local = Data()
        local += Self.le32(0x0403_4b50); local += Self.le16(20); local += Self.le16(0x0800)
        local += Self.le16(0); local += Self.le16(0); local += Self.le16(0x21)
        local += Self.le32(crc); local += Self.le32(size); local += Self.le32(size)
        local += Self.le16(n.count); local += Self.le16(0); local += n
        var cd = Data()
        cd += Self.le32(0x0201_4b50); cd += Self.le16(20); cd += Self.le16(20); cd += Self.le16(0x0800)
        cd += Self.le16(0); cd += Self.le16(0); cd += Self.le16(0x21)
        cd += Self.le32(crc); cd += Self.le32(size); cd += Self.le32(size)
        cd += Self.le16(n.count); cd += Self.le16(0); cd += Self.le16(0)
        cd += Self.le16(0); cd += Self.le16(0); cd += Self.le32(0)
        cd += Self.le32(UInt32(offset)); cd += n
        try handle.write(contentsOf: local)
        try handle.write(contentsOf: data)
        offset += UInt64(local.count + data.count)
        central += cd
        count += 1
    }

    func finish() throws {
        var end = Data()
        end += Self.le32(0x0605_4b50); end += Self.le16(0); end += Self.le16(0)
        end += Self.le16(count); end += Self.le16(count)
        end += Self.le32(UInt32(central.count)); end += Self.le32(UInt32(offset)); end += Self.le16(0)
        try handle.write(contentsOf: central)
        try handle.write(contentsOf: end)
        try handle.close()
    }
}

// MARK: - Zip reading (stored and deflate, zip64 aware)

/// Reads the backup back, or a zip of the same files made elsewhere (the
/// Files app's Compress writes deflate). The file is memory-mapped, not read.
struct SaveZipReader {
    struct Entry { let name: String; let method: Int; let compressedSize: Int; let size: Int; let localOffset: Int }

    private let data: Data
    let entries: [Entry]

    init(url: URL) throws {
        let b = try Data(contentsOf: url, options: .alwaysMapped)
        data = b
        func fail(_ m: String) -> Error { SaveError.message(m) }
        func u16(_ o: Int) throws -> Int {
            guard o >= 0, o + 2 <= b.count else { throw fail("The zip is truncated.") }
            return Int(b[b.startIndex + o]) | Int(b[b.startIndex + o + 1]) << 8
        }
        func u32(_ o: Int) throws -> Int { let lo = try u16(o), hi = try u16(o + 2); return lo | hi << 16 }
        func u64(_ o: Int) throws -> Int {
            let lo = try u32(o), hi = try u32(o + 4)
            guard hi < 0x10000 else { throw fail("The zip is too large.") }
            return lo | hi << 32
        }
        guard b.count >= 22 else { throw fail("Not a zip file.") }
        var eocd = -1
        var p = b.count - 22
        let lowest = max(0, b.count - 22 - 65_535)
        while p >= lowest {
            if try u32(p) == 0x0605_4b50 { eocd = p; break }
            p -= 1
        }
        guard eocd >= 0 else { throw fail("Not a zip file.") }
        var count = try u16(eocd + 10)
        var cdOffset = try u32(eocd + 16)
        if count == 0xFFFF || cdOffset == 0xFFFF_FFFF {
            let loc = eocd - 20
            guard try u32(loc) == 0x0706_4b50 else { throw fail("Broken zip64 record.") }
            let z = try u64(loc + 8)
            guard try u32(z) == 0x0606_4b50 else { throw fail("Broken zip64 record.") }
            count = try u64(z + 32)
            cdOffset = try u64(z + 48)
        }
        var list: [Entry] = []
        var q = cdOffset
        for _ in 0..<count {
            guard try u32(q) == 0x0201_4b50 else { throw fail("Broken zip directory.") }
            let method = try u16(q + 10)
            var csize = try u32(q + 20)
            var usize = try u32(q + 24)
            let nlen = try u16(q + 28), elen = try u16(q + 30), clen = try u16(q + 32)
            var loff = try u32(q + 42)
            guard q + 46 + nlen <= b.count else { throw fail("The zip is truncated.") }
            let start = b.startIndex + q + 46
            let name = String(decoding: b[start..<(start + nlen)], as: UTF8.self)
            // zip64 extra field: the 0xFFFFFFFF fields, in this order.
            var x = q + 46 + nlen
            let xend = x + elen
            while x + 4 <= xend {
                let id = try u16(x), len = try u16(x + 2)
                if id == 0x0001 {
                    var f = x + 4
                    if usize == 0xFFFF_FFFF { usize = try u64(f); f += 8 }
                    if csize == 0xFFFF_FFFF { csize = try u64(f); f += 8 }
                    if loff == 0xFFFF_FFFF { loff = try u64(f) }
                }
                x += 4 + len
            }
            list.append(Entry(name: name, method: method, compressedSize: csize, size: usize, localOffset: loff))
            q += 46 + nlen + elen + clen
        }
        entries = list
    }

    func extract(_ e: Entry) throws -> Data {
        let b = data
        let o = e.localOffset
        guard o >= 0, o + 30 <= b.count,
              b[b.startIndex + o] == 0x50, b[b.startIndex + o + 1] == 0x4b,
              b[b.startIndex + o + 2] == 0x03, b[b.startIndex + o + 3] == 0x04 else {
            throw SaveError.message("Broken zip entry \(e.name).")
        }
        let nlen = Int(b[b.startIndex + o + 26]) | Int(b[b.startIndex + o + 27]) << 8
        let elen = Int(b[b.startIndex + o + 28]) | Int(b[b.startIndex + o + 29]) << 8
        let start = o + 30 + nlen + elen
        guard e.compressedSize >= 0, start + e.compressedSize <= b.count else { throw SaveError.message("The zip is truncated.") }
        let src = b.subdata(in: (b.startIndex + start)..<(b.startIndex + start + e.compressedSize))
        switch e.method {
        case 0:
            return src
        case 8:
            if e.size == 0 { return Data() }
            var out = Data(count: e.size)
            let written: Int = out.withUnsafeMutableBytes { dst in
                src.withUnsafeBytes { s in
                    guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                          let sp = s.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(d, e.size, sp, s.count, nil, COMPRESSION_ZLIB)
                }
            }
            guard written == e.size else { throw SaveError.message("\(e.name) could not be decompressed.") }
            return out
        default:
            throw SaveError.message("\(e.name) uses zip method \(e.method), which is not supported.")
        }
    }
}

// MARK: - Save backups

enum SaveBackup {
    /// Folders under each C:\users\<name> that hold saves and settings.
    static let roots = ["Documents", "Saved Games", "AppData/Roaming", "AppData/LocalLow", "AppData/Local"]
    /// Folder names that are caches or Windows' own files, never saves.
    /// "steam" and "htmlcache": the Steam client Madeira Dock runs keeps its sign-in
    /// state (local.vdf) and web cookies under AppData\Local\Steam; never in a backup.
    static let skipped: Set<String> = ["madeira", "temp", "shadercache", "d3dscache", "nvidia", "microsoft",
                                       "cache", "caches", "crashdumps", "logs", "webcache", "steam", "htmlcache"]
    static let maxFile = 256 << 20
    static let maxTotal: UInt64 = 3_500 << 20

    struct BackupResult { let url: URL; let files: Int; let bytes: UInt64; let leftOut: Int }

    /// One file a backup would hold.
    struct Item { let name: String; let url: URL; let size: Int; let modified: Double }

    /// The files a backup would hold, named from drive_c ("users/<name>/Documents/..."), which is where restore puts them. Files over `maxFile`, links and the skipped
    /// folders are left out; `tooLarge` counts the ones left out for size.
    static func scan() -> (items: [Item], tooLarge: Int) {
        let fm = FileManager.default
        let drive = AppModel.driveC
        let users = drive.appendingPathComponent("users", isDirectory: true)
        var items: [Item] = [], tooLarge = 0
        for user in ((try? fm.contentsOfDirectory(atPath: users.path)) ?? []).sorted() {
            for root in roots {
                let base = "users/\(user)/\(root)"
                let dir = drive.appendingPathComponent(base, isDirectory: true)
                // Relative paths, so entry names never depend on how the container path is spelled (/var or /private/var).
                guard let e = fm.enumerator(atPath: dir.path) else { continue }
                while let rel = e.nextObject() as? String {
                    let type = e.fileAttributes?[.type] as? FileAttributeType
                    if type == .typeDirectory {
                        if skipped.contains((rel as NSString).lastPathComponent.lowercased()) { e.skipDescendants() }
                        continue
                    }
                    guard type == .typeRegular else { continue }   // links are not followed
                    let size = (e.fileAttributes?[.size] as? NSNumber)?.intValue ?? 0
                    if size > maxFile { tooLarge += 1; continue }
                    let modified = (e.fileAttributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                    items.append(Item(name: base + "/" + rel, url: dir.appendingPathComponent(rel), size: size, modified: modified))
                }
            }
        }
        return (items, tooLarge)
    }

    /// "2026-10-07_04-47-36" in local time, from the C library: a DateFormatter would go through ICU, which crashed right after a game was ended in a session whose
    /// pseudo-process had just been torn down (a read of unmapped memory inside SimpleDateFormat, 2026-10-07), and this runs on a thread of its own at that moment.
    static func fileStamp(_ date: Date) -> String {
        var t = time_t(date.timeIntervalSince1970), parts = tm()
        localtime_r(&t, &parts)
        var buffer = [CChar](repeating: 0, count: 32)
        strftime(&buffer, buffer.count, "%Y-%m-%d_%H-%M-%S", &parts)
        return String(cString: buffer)
    }

    /// Writes the zip into `directory` (default: the temporary directory).
    static func backup(into directory: URL? = nil, namePrefix: String = "Porthole-saves") throws -> BackupResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: AppModel.driveC.appendingPathComponent("users").path) else { throw SaveError.message("There is no Windows drive yet.") }
        let folder = directory ?? fm.temporaryDirectory
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        // Two backups in the same second get different names; nothing is ever overwritten.
        let base = "\(namePrefix)-\(fileStamp(Date()))"
        var out = folder.appendingPathComponent("\(base).zip"), n = 2
        while fm.fileExists(atPath: out.path) { out = folder.appendingPathComponent("\(base)-\(n).zip"); n += 1 }
        let zip = try SaveZipWriter(url: out)
        let scanned = scan()
        var leftOut = scanned.tooLarge
        for item in scanned.items {
            if zip.offset + UInt64(item.size) > maxTotal || zip.count >= SaveZipWriter.maxEntries { leftOut += 1; continue }
            guard let data = try? Data(contentsOf: item.url) else { continue }
            try zip.add(name: item.name, data: data)
        }
        try zip.finish()
        LogStore.shared.log("[saves] backup: \(zip.count) files, \(zip.offset) bytes, \(leftOut) left out")
        return BackupResult(url: out, files: zip.count, bytes: zip.offset, leftOut: leftOut)
    }

    /// Puts a backup's files back (overwriting). Only entries under users/.
    static func restore(from url: URL) throws -> Int {
        let drive = AppModel.driveC
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let zip = try SaveZipReader(url: url)
        let fm = FileManager.default
        var n = 0
        for e in zip.entries where !e.name.hasSuffix("/") {
            let parts = e.name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3, parts[0].lowercased() == "users",
                  !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { continue }
            let dst = parts.reduce(drive) { $0.appendingPathComponent($1) }
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try zip.extract(e).write(to: dst, options: .atomic)
            n += 1
        }
        if n == 0 { throw SaveError.message("That zip holds no saves (nothing under users/).") }
        LogStore.shared.log("[saves] restored \(n) files from \(url.lastPathComponent)")
        return n
    }
}

