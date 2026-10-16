// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import CryptoKit

// Small binary formats used by Apple's remote pairing protocol. Written from the protocol as documented by the open-source idevice project
// (Jackson Coxson) and the StikPair app (StephenDev0 / the StikDebug team); see PairingCredits.

// MARK: TLV8

/// Pairing data components (HomeKit-style TLV8 type codes).
enum PairingTLVType: UInt8 {
    case method = 0x00, identifier = 0x01, salt = 0x02, publicKey = 0x03, proof = 0x04, encryptedData = 0x05, state = 0x06
    case errorResponse = 0x07, retryDelay = 0x08, certificate = 0x09, signature = 0x0a, permissions = 0x0b, fragmentData = 0x0c
    case fragmentLast = 0x0d, sessionID = 0x0e, ttl = 0x0f, extraData = 0x10, info = 0x11, acl = 0x12, flags = 0x13
    case validationData = 0x14, mfiAuthToken = 0x15, mfiProductType = 0x16, serialNumber = 0x17, mfiAuthTokenUUID = 0x18
    case appFlags = 0x19, ownershipProof = 0x1a, setupCodeType = 0x1b, productionData = 0x1c, appInfo = 0x1d, separator = 0xff
}

struct PairingTLV {
    var type: PairingTLVType
    var data: [UInt8]

    /// A value longer than 255 bytes is split into consecutive entries of the same type.
    static func chunked(_ type: PairingTLVType, _ data: [UInt8]) -> [PairingTLV] {
        stride(from: 0, to: max(data.count, 1), by: 255).map { PairingTLV(type: type, data: Array(data[$0..<min($0 + 255, data.count)])) }
    }

    static func serialize(_ entries: [PairingTLV]) -> [UInt8] {
        var out: [UInt8] = []
        for e in entries { out.append(e.type.rawValue); out.append(UInt8(e.data.count)); out.append(contentsOf: e.data) }
        return out
    }

    static func parse(_ bytes: [UInt8]) throws -> [PairingTLV] {
        var out: [PairingTLV] = []
        var i = 0
        while i + 2 <= bytes.count {
            let t = bytes[i], len = Int(bytes[i + 1]); i += 2
            guard i + len <= bytes.count else { throw PairingError.malformed("TLV entry runs past the end") }
            guard let type = PairingTLVType(rawValue: t) else { throw PairingError.malformed("unknown TLV type \(t)") }
            out.append(PairingTLV(type: type, data: Array(bytes[i..<(i + len)]))); i += len
        }
        return out
    }

    /// All data of one type, joined (a long value arrives as several entries).
    static func joined(_ entries: [PairingTLV], _ type: PairingTLVType) -> [UInt8] {
        entries.filter { $0.type == type }.flatMap(\.data)
    }
}

enum PairingError: LocalizedError {
    case malformed(String)
    case unexpected(String)
    case wrongPIN
    case cancelled
    case network(String)

    var errorDescription: String? {
        switch self {
        case .malformed(let s): "The iPhone sent something unreadable (\(s))."
        case .unexpected(let s): "Pairing went off script: \(s)."
        case .wrongPIN: "The code was wrong. Start again and type the new code."
        case .cancelled: "Pairing was cancelled."
        case .network(let s): s
        }
    }
}

// MARK: OPACK

/// Apple's compact binary serialisation. Only the types the pairing messages use.
enum OPACK {
    indirect enum Value: Equatable {
        case bool(Bool), int(UInt64), string(String), data([UInt8]), array([Value]), dict([(String, Value)]), real(Double)
        static func == (l: Value, r: Value) -> Bool {
            switch (l, r) {
            case (.bool(let a), .bool(let b)): a == b
            case (.int(let a), .int(let b)): a == b
            case (.string(let a), .string(let b)): a == b
            case (.data(let a), .data(let b)): a == b
            case (.real(let a), .real(let b)): a == b
            case (.array(let a), .array(let b)): a == b
            case (.dict(let a), .dict(let b)): a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
            default: false
            }
        }
        subscript(key: String) -> Value? {
            if case .dict(let pairs) = self { return pairs.first { $0.0 == key }?.1 }
            return nil
        }
        var stringValue: String? { if case .string(let s) = self { s } else { nil } }
        var dataValue: [UInt8]? { if case .data(let d) = self { d } else { nil } }
    }

    static func encode(_ value: Value) -> [UInt8] { var out: [UInt8] = []; write(value, &out); return out }

    private static func write(_ value: Value, _ out: inout [UInt8]) {
        switch value {
        case .dict(let pairs):
            if pairs.count < 15 { out.append(UInt8(0xE0 + pairs.count)) } else { out.append(0xEF) }
            for (k, v) in pairs { write(.string(k), &out); write(v, &out) }
            if pairs.count > 14 { out.append(0x03) }
        case .array(let items):
            if items.count < 15 { out.append(UInt8(0xD0 + items.count)) } else { out.append(0xDF) }
            for v in items { write(v, &out) }
            if items.count > 14 { out.append(0x03) }
        case .bool(let b): out.append(b ? 1 : 2)
        case .int(let n):
            if n <= 0x27 { out.append(UInt8(n) + 8) }
            else if n <= 0xFF { out.append(0x30); out.append(UInt8(n)) }
            else if n <= 0xFFFF_FFFF { out.append(0x32); out.append(contentsOf: withUnsafeBytes(of: UInt32(n).littleEndian, Array.init)) }
            else { out.append(0x33); out.append(contentsOf: withUnsafeBytes(of: n.littleEndian, Array.init)) }
        case .real(let d):
            out.append(0x36); out.append(contentsOf: withUnsafeBytes(of: d.bitPattern.bigEndian, Array.init))
        case .string(let s):
            let b = Array(s.utf8)
            if b.count <= 0x20 { out.append(UInt8(0x40 + b.count)) }
            else if b.count <= 0xFF { out.append(0x61); out.append(UInt8(b.count)) }
            else if b.count <= 0xFFFF { out.append(0x62); out.append(contentsOf: withUnsafeBytes(of: UInt16(b.count).littleEndian, Array.init)) }
            else { out.append(0x63); out.append(contentsOf: withUnsafeBytes(of: UInt32(b.count).littleEndian, Array.init)) }
            out.append(contentsOf: b)
        case .data(let b):
            if b.count <= 0x20 { out.append(UInt8(0x70 + b.count)) }
            else if b.count <= 0xFF { out.append(0x91); out.append(UInt8(b.count)) }
            else if b.count <= 0xFFFF { out.append(0x92); out.append(contentsOf: withUnsafeBytes(of: UInt16(b.count).littleEndian, Array.init)) }
            else { out.append(0x93); out.append(contentsOf: withUnsafeBytes(of: UInt32(b.count).littleEndian, Array.init)) }
            out.append(contentsOf: b)
        }
    }

    static func decode(_ bytes: [UInt8]) throws -> Value {
        var i = 0
        let v = try read(bytes, &i)
        return v
    }

    private static func take(_ bytes: [UInt8], _ i: inout Int, _ n: Int) throws -> ArraySlice<UInt8> {
        guard n >= 0, i + n <= bytes.count else { throw PairingError.malformed("OPACK ended early") }
        defer { i += n }
        return bytes[i..<(i + n)]
    }
    private static func le(_ s: ArraySlice<UInt8>) -> UInt64 { s.enumerated().reduce(0) { $0 | (UInt64($1.element) << UInt64(8 * $1.offset)) } }

    private static func read(_ bytes: [UInt8], _ i: inout Int) throws -> Value {
        let tag = try take(bytes, &i, 1).first!
        switch tag {
        case 0x01: return .bool(true)
        case 0x02: return .bool(false)
        case 0x08...0x2F: return .int(UInt64(tag) - 8)
        case 0x30: return .int(le(try take(bytes, &i, 1)))
        case 0x31: return .int(le(try take(bytes, &i, 2)))
        case 0x32: return .int(le(try take(bytes, &i, 4)))
        case 0x33: return .int(le(try take(bytes, &i, 8)))
        case 0x35: return .real(Double(Float(bitPattern: UInt32(try take(bytes, &i, 4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }))))
        case 0x36: return .real(Double(bitPattern: try take(bytes, &i, 8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }))
        case 0x40...0x64:
            let n = try length(tag, base: 0x40, first: 0x61, bytes, &i)
            guard let s = String(bytes: try take(bytes, &i, n), encoding: .utf8) else { throw PairingError.malformed("OPACK string is not UTF-8") }
            return .string(s)
        case 0x70...0x94:
            let n = try length(tag, base: 0x70, first: 0x91, bytes, &i)
            return .data(Array(try take(bytes, &i, n)))
        case 0xD0...0xDF:
            var items: [Value] = []
            if tag == 0xDF { while bytes.indices.contains(i), bytes[i] != 0x03 { items.append(try read(bytes, &i)) }; i += 1 }
            else { for _ in 0..<Int(tag - 0xD0) { items.append(try read(bytes, &i)) } }
            return .array(items)
        case 0xE0...0xEF:
            var pairs: [(String, Value)] = []
            func entry() throws { guard case .string(let k) = try read(bytes, &i) else { throw PairingError.malformed("OPACK key is not a string") }; pairs.append((k, try read(bytes, &i))) }
            if tag == 0xEF { while bytes.indices.contains(i), bytes[i] != 0x03 { try entry() }; i += 1 }
            else { for _ in 0..<Int(tag - 0xE0) { try entry() } }
            return .dict(pairs)
        default: throw PairingError.malformed(String(format: "unsupported OPACK tag 0x%02x", tag))
        }
    }

    private static func length(_ tag: UInt8, base: UInt8, first: UInt8, _ bytes: [UInt8], _ i: inout Int) throws -> Int {
        if tag < first { return Int(tag - base) }
        let width = [1, 2, 4, 8][Int(tag - first)]
        return Int(le(try take(bytes, &i, width)))
    }
}

// MARK: Identity helpers

enum PairingIdentity {
    /// SipHash-2-4 (64-bit output) with a 128-bit key.
    static func sipHash24(key: [UInt8], message: [UInt8]) -> UInt64 {
        func u64(_ b: ArraySlice<UInt8>) -> UInt64 { b.enumerated().reduce(0) { $0 | (UInt64($1.element) << UInt64(8 * $1.offset)) } }
        let k0 = u64(key[0..<8]), k1 = u64(key[8..<16])
        var v0 = k0 ^ 0x736f6d6570736575, v1 = k1 ^ 0x646f72616e646f6d, v2 = k0 ^ 0x6c7967656e657261, v3 = k1 ^ 0x7465646279746573
        func rotl(_ x: UInt64, _ b: UInt64) -> UInt64 { (x << b) | (x >> (64 - b)) }
        func round() {
            v0 = v0 &+ v1; v1 = rotl(v1, 13); v1 ^= v0; v0 = rotl(v0, 32)
            v2 = v2 &+ v3; v3 = rotl(v3, 16); v3 ^= v2
            v0 = v0 &+ v3; v3 = rotl(v3, 21); v3 ^= v0
            v2 = v2 &+ v1; v1 = rotl(v1, 17); v1 ^= v2; v2 = rotl(v2, 32)
        }
        let full = message.count / 8
        for i in 0..<full {
            let m = u64(message[(i * 8)..<(i * 8 + 8)])
            v3 ^= m; round(); round(); v0 ^= m
        }
        var last = UInt64(message.count & 0xFF) << 56
        for (j, b) in message[(full * 8)...].enumerated() { last |= UInt64(b) << UInt64(8 * j) }
        v3 ^= last; round(); round(); v0 ^= last
        v2 ^= 0xFF
        round(); round(); round(); round()
        return v0 ^ v1 ^ v2 ^ v3
    }

    /// The 6-byte tag a pairable host puts in its Bonjour record so a device that already knows it can recognise it:
    /// SipHash-2-4 keyed with the host's altIRK over the service identifier, first six bytes of the little-endian result, in reverse order.
    static func authTag(altIRK: [UInt8], serviceIdentifier: String) -> [UInt8] {
        let h = sipHash24(key: altIRK, message: Array(serviceIdentifier.utf8))
        let le = withUnsafeBytes(of: h.littleEndian, Array.init)
        return (0..<6).map { le[5 - $0] }
    }

    /// RFC 4122 version-3 (MD5, name-based) UUID in the DNS namespace.
    static func uuidV3(dnsName: String) -> String {
        let namespace: [UInt8] = [0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1, 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8]
        var hash = Array(Insecure.MD5.hash(data: Data(namespace + Array(dnsName.utf8))))
        hash[6] = (hash[6] & 0x0F) | 0x30
        hash[8] = (hash[8] & 0x3F) | 0x80
        let h = hash.map { String(format: "%02x", $0) }.joined()
        return "\(h.prefix(8))-\(h.dropFirst(8).prefix(4))-\(h.dropFirst(12).prefix(4))-\(h.dropFirst(16).prefix(4))-\(h.dropFirst(20))"
    }
}
