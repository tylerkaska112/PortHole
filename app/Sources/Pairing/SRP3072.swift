// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import CryptoKit

/// The server half of the SRP-6a exchange Apple uses for pair-setup (RFC 5054's 3072-bit group, SHA-512).
///
/// Apple's variant differs from the textbook one in a few places, all reproduced here: the key is SHA-512 of the premaster secret with leading zeros
/// stripped; the scrambler u hashes A and B with leading zeros stripped; and the client proof M1 is H(H(N) xor H(g) | H(user) | salt | A | B | K) with
/// A and B padded to the modulus length.
struct SRP3072Server {
    /// The RFC 3526 / RFC 5054 3072-bit prime.
    static let primeHex =
        "ffffffffffffffffc90fdaa22168c234c4c6628b80dc1cd129024e088a67cc74020bbea63b139b22514a08798e3404ddef9519b3cd3a431b302b0a6df25f14374fe1356d6d51c245e485b576625e7ec6f44c42e9a637ed6b0bff5cb6f406b7edee386bfb5a899fa5ae9f24117c4b1fe649286651ece45b3dc2007cb8a163bf0598da48361c55d39a69163fa8fd24cf5f83655d23dca3ad961c62f356208552bb9ed529077096966d670c354e4abc9804f1746c08ca18217c32905e462e36ce3be39e772c180e86039b2783a2ec07a28fb5c55df06f4c52c9de2bcbf6955817183995497cea956ae515d2261898fa051015728e5a8aaac42dad33170d04507a33a85521abdf1cba64ecfb850458dbef0a8aea71575d060c7db3970f85a6e1e4c7abf5ae8cdb0933d71e8c94e04a25619dcee3d2261ad2ee6bf12ffa06d98a0864d87602733ec86a64521f2b18177b200cbbe117577a615d6c770988c0bad946e208e24fa074e5ab3143db5bfce0fd108e4b82d120a93ad2caffffffffffffffff"
    static let generator: UInt8 = 5

    let arithmetic: ModularArithmetic
    private let nBytes: [UInt8]
    private let k: [UInt8]                       // H(N | PAD(g)) as 64 big-endian bytes

    init() {
        var bytes: [UInt8] = []
        var i = Self.primeHex.startIndex
        while i < Self.primeHex.endIndex { let j = Self.primeHex.index(i, offsetBy: 2); bytes.append(UInt8(Self.primeHex[i..<j], radix: 16)!); i = j }
        nBytes = bytes
        arithmetic = ModularArithmetic(modulusBigEndian: bytes)
        var paddedG = [UInt8](repeating: 0, count: bytes.count); paddedG[bytes.count - 1] = Self.generator
        k = Array(SHA512.hash(data: Data(bytes + paddedG)))
    }

    private func element(_ bytes: [UInt8]) -> ModularArithmetic.Limbs { arithmetic.element(fromBigEndian: bytes) }
    private func bytes(_ e: ModularArithmetic.Limbs) -> [UInt8] { ModularArithmetic.bigEndian(e) }
    private var g: ModularArithmetic.Limbs { element([Self.generator]) }

    private func strip(_ b: [UInt8]) -> [UInt8] { var o = b; while o.count > 1, o.first == 0 { o.removeFirst() }; return o }
    private func pad(_ b: [UInt8]) -> [UInt8] { [UInt8](repeating: 0, count: max(nBytes.count - b.count, 0)) + b }

    /// The password verifier v = g^x for a username and PIN: x = H(salt | H(username ":" password)).
    func verifier(username: [UInt8], password: [UInt8], salt: [UInt8]) -> [UInt8] {
        let identity = Array(SHA512.hash(data: Data(username + [0x3A] + password)))
        let x = Array(SHA512.hash(data: Data(salt + identity)))
        return bytes(arithmetic.power(g, exponentBigEndian: x))
    }

    /// The server's public value B = (k*v + g^b) mod N, as bytes with leading zeros removed.
    func publicValue(privateB: [UInt8], verifier v: [UInt8]) -> [UInt8] {
        let kv = arithmetic.multiply(element(k), element(v))
        let gb = arithmetic.power(g, exponentBigEndian: privateB)
        return bytes(arithmetic.add(kv, gb))
    }

    struct Session {
        let key: [UInt8]               // K, 64 bytes
        let clientProof: [UInt8]       // M1 the client must send
        let serverProof: [UInt8]       // M2 we send back
    }

    enum SRPError: Error { case illegalParameter }

    /// Works out the shared key and both proofs after the client's public value A arrives.
    func process(privateB: [UInt8], publicB: [UInt8]? = nil, verifier v: [UInt8], clientPublic aBytes: [UInt8], username: [UInt8], salt: [UInt8]) throws -> Session {
        let aReduced = element(aBytes)
        if arithmetic.isZero(aReduced) { throw SRPError.illegalParameter }
        let a = strip(aBytes)
        let b = publicB ?? publicValue(privateB: privateB, verifier: v)
        let u = Array(SHA512.hash(data: Data(a + b)))
        // S = (A * v^u)^b mod N
        let vu = arithmetic.power(element(v), exponentBigEndian: u)
        let base = arithmetic.multiply(aReduced, vu)
        let s = bytes(arithmetic.power(base, exponentBigEndian: privateB))
        let key = Array(SHA512.hash(data: Data(s)))

        let hN = Array(SHA512.hash(data: Data(nBytes)))
        let hg = Array(SHA512.hash(data: Data([Self.generator])))
        let hng = zip(hg, hN).map { $0 ^ $1 }
        let m1 = Array(SHA512.hash(data: Data(hng + Array(SHA512.hash(data: Data(username))) + salt + pad(a) + pad(b) + key)))
        let m2 = Array(SHA512.hash(data: Data(a + m1 + key)))
        return Session(key: key, clientProof: m1, serverProof: m2)
    }
}
