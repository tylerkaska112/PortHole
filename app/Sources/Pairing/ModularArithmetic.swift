// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Big-number arithmetic modulo a fixed odd modulus (Montgomery form). SRP-3072 needs a handful of 3072-bit modular multiplications and
/// exponentiations; Swift has no big integers, so this is the small amount of maths required and nothing more.
///
/// Numbers are little-endian arrays of 64-bit limbs, always exactly `limbCount` long and always smaller than the modulus.
struct ModularArithmetic {
    typealias Limbs = [UInt64]

    let modulus: Limbs
    let limbCount: Int
    private let n0inv: UInt64          // -modulus^-1 mod 2^64
    private let rSquared: Limbs        // 2^(128 * limbCount) mod modulus

    /// `modulus` as big-endian bytes (must be odd).
    init(modulusBigEndian bytes: [UInt8]) {
        let limbs = Self.limbs(fromBigEndian: bytes)
        precondition(limbs.first.map { $0 & 1 == 1 } ?? false, "the modulus must be odd")
        modulus = limbs
        limbCount = limbs.count
        // Newton iteration for the inverse of m0 modulo 2^64.
        var inverse: UInt64 = limbs[0]
        for _ in 0..<6 { inverse = inverse &* (2 &- limbs[0] &* inverse) }
        n0inv = 0 &- inverse
        // 2^(128 n) mod N by repeated doubling.
        var x = [UInt64](repeating: 0, count: limbs.count); x[0] = 1
        for _ in 0..<(128 * limbs.count) { x = Self.doubleMod(x, limbs) }
        rSquared = x
    }

    // MARK: Conversion

    static func limbs(fromBigEndian bytes: [UInt8], count: Int? = nil) -> Limbs {
        let needed = max((bytes.count + 7) / 8, 1)
        let n = max(count ?? needed, needed)
        var out = [UInt64](repeating: 0, count: n)
        for (i, byte) in bytes.reversed().enumerated() { out[i / 8] |= UInt64(byte) << UInt64(8 * (i % 8)) }
        return out
    }

    /// Big-endian bytes without leading zeros (empty for zero is returned as a single 0 byte).
    static func bigEndian(_ limbs: Limbs) -> [UInt8] {
        var out: [UInt8] = []
        for limb in limbs.reversed() { for shift in stride(from: 56, through: 0, by: -8) { out.append(UInt8((limb >> UInt64(shift)) & 0xFF)) } }
        while out.count > 1, out.first == 0 { out.removeFirst() }
        return out
    }

    /// Converts big-endian bytes to limbs of the modulus' width, reducing by one subtraction if the value is at most just above the modulus.
    func element(fromBigEndian bytes: [UInt8]) -> Limbs {
        var v = Self.limbs(fromBigEndian: bytes, count: limbCount)
        if v.count > limbCount { v = Array(v.prefix(limbCount)) }
        if Self.compare(v, modulus) >= 0 { v = Self.sub(v, modulus) }
        return v
    }

    var one: Limbs { var x = [UInt64](repeating: 0, count: limbCount); x[0] = 1; return x }

    // MARK: Operations

    func isZero(_ a: Limbs) -> Bool { !a.contains { $0 != 0 } }

    func add(_ a: Limbs, _ b: Limbs) -> Limbs {
        var out = a
        var carry: UInt64 = 0
        for i in 0..<limbCount {
            let (s1, o1) = a[i].addingReportingOverflow(b[i])
            let (s2, o2) = s1.addingReportingOverflow(carry)
            out[i] = s2; carry = (o1 ? 1 : 0) + (o2 ? 1 : 0)
        }
        if carry != 0 || Self.compare(out, modulus) >= 0 { out = Self.sub(out, modulus) }
        return out
    }

    /// a * b mod N, for a and b already below N.
    func multiply(_ a: Limbs, _ b: Limbs) -> Limbs { montMul(montMul(a, rSquared), b) }

    /// base^exponent mod N. `exponent` is big-endian bytes.
    func power(_ base: Limbs, exponentBigEndian exponent: [UInt8]) -> Limbs {
        var result = montMul(one, rSquared)               // 1 in Montgomery form
        let b = montMul(base, rSquared)                   // base in Montgomery form
        for byte in exponent {
            for bit in stride(from: 7, through: 0, by: -1) {
                result = montMul(result, result)
                if (byte >> UInt8(bit)) & 1 == 1 { result = montMul(result, b) }
            }
        }
        return montMul(result, one)                       // back out of Montgomery form
    }

    // MARK: Internals

    /// Montgomery product a * b / 2^(64 n) mod N (CIOS).
    private func montMul(_ a: Limbs, _ b: Limbs) -> Limbs {
        let n = limbCount
        var t = [UInt64](repeating: 0, count: n + 2)
        for i in 0..<n {
            var carry: UInt64 = 0
            let bi = b[i]
            for j in 0..<n {
                let (hi, lo) = a[j].multipliedFullWidth(by: bi)
                let (s1, o1) = lo.addingReportingOverflow(t[j])
                let (s2, o2) = s1.addingReportingOverflow(carry)
                t[j] = s2
                carry = hi &+ (o1 ? 1 : 0) &+ (o2 ? 1 : 0)
            }
            let (s, o) = t[n].addingReportingOverflow(carry)
            t[n] = s
            t[n + 1] = o ? 1 : 0

            let m = t[0] &* n0inv
            var (hi, lo) = m.multipliedFullWidth(by: modulus[0])
            let (_, oFirst) = lo.addingReportingOverflow(t[0])
            carry = hi &+ (oFirst ? 1 : 0)
            for j in 1..<n {
                (hi, lo) = m.multipliedFullWidth(by: modulus[j])
                let (s1, o1) = lo.addingReportingOverflow(t[j])
                let (s2, o2) = s1.addingReportingOverflow(carry)
                t[j - 1] = s2
                carry = hi &+ (o1 ? 1 : 0) &+ (o2 ? 1 : 0)
            }
            let (s3, o3) = t[n].addingReportingOverflow(carry)
            t[n - 1] = s3
            t[n] = t[n + 1] &+ (o3 ? 1 : 0)
        }
        var out = Array(t[0..<n])
        if t[n] != 0 || Self.compare(out, modulus) >= 0 { out = Self.sub(out, modulus) }
        return out
    }

    private static func compare(_ a: Limbs, _ b: Limbs) -> Int {
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            if a[i] != b[i] { return a[i] > b[i] ? 1 : -1 }
        }
        return 0
    }

    /// a - b (wraps around modulo 2^(64 n), which is what the callers want when a carry was dropped).
    private static func sub(_ a: Limbs, _ b: Limbs) -> Limbs {
        var out = a
        var borrow: UInt64 = 0
        for i in 0..<a.count {
            let (d1, o1) = a[i].subtractingReportingOverflow(b[i])
            let (d2, o2) = d1.subtractingReportingOverflow(borrow)
            out[i] = d2; borrow = (o1 ? 1 : 0) + (o2 ? 1 : 0)
        }
        return out
    }

    private static func doubleMod(_ x: Limbs, _ m: Limbs) -> Limbs {
        var out = x
        var carry: UInt64 = 0
        for i in 0..<x.count {
            let next = x[i] >> 63
            out[i] = (x[i] << 1) | carry
            carry = next
        }
        if carry != 0 || compare(out, m) >= 0 { out = sub(out, m) }
        return out
    }
}
