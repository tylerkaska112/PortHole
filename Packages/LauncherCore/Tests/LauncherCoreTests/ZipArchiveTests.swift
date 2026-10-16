// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Testing
import Foundation
@testable import LauncherCore

@Suite struct ZipArchiveTests {
    /// The one-byte-at-a-time version the fast checksum replaced.
    private func slowCRC(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for n in 0..<256 { var c = UInt32(n); for _ in 0..<8 { c = c & 1 == 1 ? 0xedb88320 ^ (c >> 1) : c >> 1 }; table[n] = c }
        var crc: UInt32 = 0xffff_ffff
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return crc ^ 0xffff_ffff
    }

    @Test func checksumMatchesTheReferenceValueAndTheSlowOne() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF43926)
        #expect(CRC32.checksum(Data()) == 0)
        var generator = SystemRandomNumberGenerator()
        for length in [1, 7, 8, 9, 63, 64, 1000, 100_003] {
            let data = Data((0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) })
            #expect(CRC32.checksum(data) == slowCRC(data), "length \(length)")
        }
    }

    @Test func roundTripKeepsEveryEntryAndUntouchedOnesAreWrittenAsTheyWere() throws {
        let compressible = Data(repeating: 0x41, count: 50_000)
        let random = Data((0..<20_000).map { _ in UInt8.random(in: 0...255) })
        let first = try ZipArchive.write([
            ZipEntry(name: "dir/", mode: 0o40755),
            ZipEntry(name: "dir/a.txt", data: compressible),
            ZipEntry(name: "dir/b.bin", data: random, mode: 0o100755),
            ZipEntry(name: "empty", data: Data()),
        ])
        var entries = try ZipArchive.read(first)
        #expect(entries.map(\.name) == ["dir/", "dir/a.txt", "dir/b.bin", "empty"])
        #expect(entries[1].data == compressible && entries[2].data == random && entries[2].mode == 0o100755)
        #expect(entries.allSatisfy { $0.packed != nil })

        // Written back untouched: the same bytes come out. Changing one entry gives that entry fresh contents and leaves the others alone.
        let again = try ZipArchive.write(entries)
        #expect(again == first)
        entries[1].data = Data("changed".utf8)
        #expect(entries[1].packed == nil && entries[2].packed != nil)
        let edited = try ZipArchive.read(try ZipArchive.write(entries))
        #expect(edited[1].data == Data("changed".utf8))
        #expect(edited[2].data == random && edited[0].isDirectory)
    }

    @Test func aDamagedEntryIsReported() throws {
        var bytes = [UInt8](try ZipArchive.write([ZipEntry(name: "a", data: Data(repeating: 0x42, count: 5000))]))
        bytes[40] ^= 0xff                      // inside the compressed data
        #expect(throws: (any Error).self) { _ = try ZipArchive.read(Data(bytes)) }
    }
}
