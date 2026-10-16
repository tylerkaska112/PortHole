// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// A thin 64-bit Mach-O executable whose load commands can be edited to make room for a code signature.
struct MachOImage {
    var bytes: [UInt8]
    /// `MH_EXECUTE` (an app's main binary) as opposed to a dylib.
    let isExecutable: Bool
    let textFileOffset: UInt64
    let textFileSize: UInt64

    private let linkeditCommand: Int
    private var signatureCommand: Int?
    /// Where the load commands must stop (the first section's data starts here).
    private let headerLimit: Int

    private static let headerSize = 32

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count > 64 else { throw SigningError.unsupportedBinary("not a Mach-O file") }
        switch Self.u32(bytes, 0) {
        case 0xfeedfacf: break
        case 0xbebafeca, 0xcafebabe: throw SigningError.unsupportedBinary("universal (fat) binaries")
        default: throw SigningError.unsupportedBinary("not a 64-bit Mach-O executable")
        }
        isExecutable = Self.u32(bytes, 12) == 2
        let count = Int(Self.u32(bytes, 16))
        var offset = Self.headerSize
        var linkedit: Int?, signature: Int?
        var textOffset: UInt64 = 0, textSize: UInt64 = 0
        var firstSection = Int.max
        for _ in 0..<count {
            guard offset + 8 <= bytes.count else { throw SigningError.unsupportedBinary("truncated load commands") }
            let command = Self.u32(bytes, offset), size = Int(Self.u32(bytes, offset + 4))
            guard size >= 8, offset + size <= bytes.count else { throw SigningError.unsupportedBinary("bad load command") }
            if command == 0x19 {   // LC_SEGMENT_64
                let name = String(decoding: bytes[offset + 8..<offset + 24].prefix { $0 != 0 }, as: UTF8.self)
                if name == "__LINKEDIT" { linkedit = offset }
                if name == "__TEXT" { textOffset = Self.u64(bytes, offset + 40); textSize = Self.u64(bytes, offset + 48) }
                for section in 0..<Int(Self.u32(bytes, offset + 64)) {
                    let sectionOffset = Int(Self.u32(bytes, offset + 72 + section * 80 + 48))
                    if sectionOffset > 0 { firstSection = min(firstSection, sectionOffset) }
                }
            }
            if command == 0x1d { signature = offset }   // LC_CODE_SIGNATURE
            offset += size
        }
        guard let linkedit else { throw SigningError.unsupportedBinary("no __LINKEDIT segment") }
        self.bytes = bytes
        linkeditCommand = linkedit
        signatureCommand = signature
        textFileOffset = textOffset
        textFileSize = textSize
        headerLimit = firstSection == Int.max ? bytes.count : firstSection
    }

    /// Does the file already carry a code signature (`LC_CODE_SIGNATURE`)?
    var hasSignature: Bool { signatureCommand != nil }

    /// The file without the signature it already has (the signature sits at the very end).
    func bytesWithoutSignature() -> [UInt8] {
        guard let command = signatureCommand else { return bytes }
        let start = Int(Self.u32(bytes, command + 8))
        return start > 0 && start <= bytes.count ? Array(bytes[0..<start]) : bytes
    }

    /// Records a signature of `size` bytes at `offset` (the end of the current bytes) in the load commands and grows
    /// `__LINKEDIT` to cover it.
    mutating func reserveSignature(offset: Int, size: Int) throws {
        if signatureCommand == nil {
            let commandsEnd = Self.headerSize + Int(Self.u32(bytes, 20))
            guard commandsEnd + 16 <= headerLimit else { throw SigningError.unsupportedBinary("no room for a signature in the header") }
            signatureCommand = commandsEnd
            Self.put32(&bytes, 16, Self.u32(bytes, 16) + 1)
            Self.put32(&bytes, 20, Self.u32(bytes, 20) + 16)
            Self.put32(&bytes, commandsEnd, 0x1d)
            Self.put32(&bytes, commandsEnd + 4, 16)
        }
        let command = signatureCommand!
        Self.put32(&bytes, command + 8, UInt32(offset))
        Self.put32(&bytes, command + 12, UInt32(size))

        let linkeditStart = Self.u64(bytes, linkeditCommand + 40)
        guard UInt64(offset) >= linkeditStart else { throw SigningError.unsupportedBinary("__LINKEDIT isn't last in the file") }
        let fileSize = UInt64(offset + size) - linkeditStart
        Self.put64(&bytes, linkeditCommand + 48, fileSize)
        Self.put64(&bytes, linkeditCommand + 32, (fileSize + 0x3fff) & ~0x3fff)   // vmsize: whole 16 KB pages
    }

    // MARK: Little-endian access

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 { UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24 }
    private static func u64(_ b: [UInt8], _ i: Int) -> UInt64 { UInt64(u32(b, i)) | UInt64(u32(b, i + 4)) << 32 }
    private static func put32(_ b: inout [UInt8], _ i: Int, _ v: UInt32) { for k in 0..<4 { b[i + k] = UInt8((v >> UInt32(8 * k)) & 0xff) } }
    private static func put64(_ b: inout [UInt8], _ i: Int, _ v: UInt64) { for k in 0..<8 { b[i + k] = UInt8((v >> UInt64(8 * k)) & 0xff) } }
}
