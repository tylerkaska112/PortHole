// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import Network
import CryptoKit

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
func unhex(_ s: String) -> [UInt8] { var out: [UInt8] = []; var i = s.startIndex; while i < s.endIndex { let j = s.index(i, offsetBy: 2); out.append(UInt8(s[i..<j], radix: 16)!); i = j }; return out }
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { failures += 1 } }

// ---- codecs
do {
    // auth tag test vector from the idevice project's tests
    let irk = [UInt8](Data(base64Encoded: "Mgp6ZGPzXM2ku9br46vsiw==")!)
    let tag = Data(PairingIdentity.authTag(altIRK: irk, serviceIdentifier: "2BE6E510-0325-4365-923E-B14C6F57DB3A")).base64EncodedString()
    check(tag == "kXjlTr2l", "authTag known vector (\(tag))")
    check(PairingIdentity.uuidV3(dnsName: "www.example.com") == "5df41881-3aed-3515-88a7-2f4a814cf09e", "uuid v3 vector (\(PairingIdentity.uuidV3(dnsName: "www.example.com")))")
    let dict: OPACK.Value = .dict([("altIRK", .data(Array(repeating: 7, count: 16))), ("name", .string("A very long name that is more than thirty-two bytes long indeed")), ("n", .int(5)), ("big", .int(70000)), ("b", .bool(true)), ("a", .array([.int(1), .int(300)]))])
    let back = try OPACK.decode(OPACK.encode(dict))
    check(back == dict, "OPACK round trip")
    let entries = PairingTLV.chunked(.publicKey, Array(repeating: 9, count: 600)) + [PairingTLV(type: .state, data: [3])]
    let parsed = try PairingTLV.parse(PairingTLV.serialize(entries))
    check(PairingTLV.joined(parsed, .publicKey).count == 600 && parsed.last?.data == [3], "TLV8 chunking")
}

// ---- SRP: Python client against the Swift server
func pythonClient(pin: String, salt: [UInt8], B: [UInt8]) -> (A: [UInt8], M1: [UInt8], K: [UInt8], M2: [UInt8]) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["python3", "\(CommandLine.arguments[1])/srp_client.py", pin, hex(salt), hex(B)]
    let pipe = Pipe(); p.standardOutput = pipe; try! p.run(); p.waitUntilExit()
    let parts = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.split(separator: " ").map { unhex(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
    return (parts[0], parts[1], parts[2], parts[3])
}
do {
    let srp = SRP3072Server()
    let salt = (0..<16).map { _ in UInt8.random(in: 0...255) }
    let user = Array("Pair-Setup".utf8)
    let v = srp.verifier(username: user, password: Array("123456".utf8), salt: salt)
    let b = (0..<32).map { _ in UInt8.random(in: 0...255) }
    let B = srp.publicValue(privateB: b, verifier: v)
    let c = pythonClient(pin: "123456", salt: salt, B: B)
    let s = try srp.process(privateB: b, verifier: v, clientPublic: c.A, username: user, salt: salt)
    check(s.key == c.K, "SRP shared key matches an independent client")
    check(s.clientProof == c.M1, "SRP client proof M1 matches")
    check(s.serverProof == c.M2, "SRP server proof M2 matches")
    let bad = pythonClient(pin: "654321", salt: salt, B: B)
    let sBad = try srp.process(privateB: b, verifier: v, clientPublic: bad.A, username: user, salt: salt)
    check(sBad.clientProof != bad.M1, "wrong PIN gives a different proof")
}

// ---- whole conversation: a fake iPhone against the host
final class FakePhone {
    let conn: NWConnection
    var seq = 0
    let q = DispatchQueue(label: "phone")
    init(port: UInt16) { conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp) }
    func start() async { await withCheckedContinuation { c in var done = false; conn.stateUpdateHandler = { s in if case .ready = s, !done { done = true; c.resume() } }; conn.start(queue: q) } }
    func readExact(_ n: Int) async throws -> [UInt8] {
        var out: [UInt8] = []
        while out.count < n {
            let chunk: [UInt8] = try await withCheckedThrowingContinuation { c in conn.receive(minimumIncompleteLength: 1, maximumLength: n - out.count) { d, _, _, e in if let e { c.resume(throwing: e) } else { c.resume(returning: [UInt8](d ?? Data())) } } }
            if chunk.isEmpty { throw PairingError.network("closed") }
            out += chunk
        }
        return out
    }
    func send(_ value: Any) async throws {
        let env: [String: Any] = ["message": ["plain": ["_0": value]], "originatedBy": "host", "sequenceNumber": seq]; seq += 1
        let json = try JSONSerialization.data(withJSONObject: env, options: [.withoutEscapingSlashes])
        let frame = Array("RPPairing".utf8) + [UInt8(json.count >> 8), UInt8(json.count & 0xFF)] + [UInt8](json)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in conn.send(content: Data(frame), completion: .contentProcessed { e in if let e { c.resume(throwing: e) } else { c.resume() } }) }
    }
    func recv() async throws -> [String: Any] {
        _ = try await readExact(9); let l = try await readExact(2); let body = try await readExact(Int(l[0]) << 8 | Int(l[1]))
        let o = try JSONSerialization.jsonObject(with: Data(body)) as! [String: Any]
        XCTCheck(o["originatedBy"] as? String == "device", "originatedBy is device")
        return ((o["message"] as! [String: Any])["plain"] as! [String: Any])["_0"] as! [String: Any]
    }
    func sendTLV(_ e: [PairingTLV]) async throws {
        try await send(["event": ["_0": ["pairingData": ["_0": ["data": Data(PairingTLV.serialize(e)).base64EncodedString(), "startNewSession": false, "kind": "setupManualPairing"]]]]])
    }
    func recvTLV() async throws -> [PairingTLV] {
        let m = try await recv()
        let b64 = ((((m["event"] as! [String: Any])["_0"] as! [String: Any])["pairingData"] as! [String: Any])["_0"] as! [String: Any])["data"] as! String
        return try PairingTLV.parse([UInt8](Data(base64Encoded: b64)!))
    }
}
func XCTCheck(_ ok: Bool, _ what: String) { if !ok { print("FAIL", what); failures += 1 } }

final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

func conversation(pinToType: String?) async -> (hostResult: Result<RemotePairingHost.Result, Error>, note: String) {
    let host = RemotePairingHost(displayName: "Porthole", advertise: false)
    let port = Box<UInt16>(0), shown = Box<String>("")
    host.onPIN = { shown.value = $0 }
    let failedNote = Box<String>("")
    host.onAttemptFailed = { failedNote.value = $0 }
    let portReady = DispatchSemaphore(value: 0)
    let hostTask = Task { () -> Result<RemotePairingHost.Result, Error> in
        do { return .success(try await host.run(portOut: { port.value = $0; portReady.signal() })) } catch { return .failure(error) }
    }
    portReady.wait()
    var note = ""
    do {
        let phone = FakePhone(port: port.value); await phone.start()
        try await phone.send(["request": ["_0": ["handshake": ["_0": ["hostOptions": ["attemptPairVerify": false], "wireProtocolVersion": 26]]]]])
        let hs = try await phone.recv()
        XCTCheck(((((hs["response"] as! [String: Any])["_1"] as! [String: Any])["handshake"] as! [String: Any])["_0"] as! [String: Any])["wireProtocolVersion"] as? Int == 26, "handshake response")
        try await phone.sendTLV([PairingTLV(type: .state, data: [1]), PairingTLV(type: .method, data: [0])])
        let m2 = try await phone.recvTLV()
        let salt = PairingTLV.joined(m2, .salt), B = PairingTLV.joined(m2, .publicKey)
        XCTCheck(B.count == 384 && salt.count == 16, "M2 has salt and a 384-byte B")
        let pin = pinToType ?? shown.value
        let c = pythonClient(pin: pin, salt: salt, B: B)
        try await phone.sendTLV([PairingTLV(type: .state, data: [3])] + PairingTLV.chunked(.publicKey, c.A) + PairingTLV.chunked(.proof, c.M1))
        let m4 = try await phone.recvTLV()
        if let err = m4.first(where: { $0.type == .errorResponse }) {
            try? await Task.sleep(nanoseconds: 300_000_000)                 // let the host report the failed attempt
            host.cancel()
            _ = await hostTask.value
            return (.failure(PairingError.wrongPIN), "device saw error \(err.data); host said: \(failedNote.value)")
        }
        XCTCheck(PairingTLV.joined(m4, .proof) == c.M2, "M4 server proof verifies")
        let key = SymmetricKey(data: c.K)
        let setup = HKDF<SHA512>.deriveKey(inputKeyMaterial: key, salt: Data("Pair-Setup-Encrypt-Salt".utf8), info: Data("Pair-Setup-Encrypt-Info".utf8), outputByteCount: 32)
        let devKey = Curve25519.Signing.PrivateKey()
        let info = OPACK.encode(.dict([("altIRK", .data(Array(repeating: 0xAB, count: 16))), ("name", .string("Test iPhone")), ("model", .string("iPhone18,1"))]))
        let plain5 = PairingTLV.serialize([PairingTLV(type: .identifier, data: Array("PHONE-ID".utf8)), PairingTLV(type: .publicKey, data: [UInt8](devKey.publicKey.rawRepresentation)), PairingTLV(type: .signature, data: Array(repeating: 1, count: 64))] + PairingTLV.chunked(.info, info))
        let box5 = try ChaChaPoly.seal(Data(plain5), using: setup, nonce: ChaChaPoly.Nonce(data: Data([0, 0, 0, 0] + Array("PS-Msg05".utf8))))
        try await phone.sendTLV(PairingTLV.chunked(.encryptedData, [UInt8](box5.ciphertext) + [UInt8](box5.tag)) + [PairingTLV(type: .state, data: [5])])
        let m6 = try await phone.recvTLV()
        let sealed = PairingTLV.joined(m6, .encryptedData)
        let box6 = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: Data([0, 0, 0, 0] + Array("PS-Msg06".utf8))), ciphertext: Data(sealed.dropLast(16)), tag: Data(sealed.suffix(16)))
        let ident = try PairingTLV.parse([UInt8](try ChaChaPoly.open(box6, using: setup)))
        let hostID = String(decoding: PairingTLV.joined(ident, .identifier), as: UTF8.self)
        let hostPub = PairingTLV.joined(ident, .publicKey), sig = PairingTLV.joined(ident, .signature)
        let accessoryX = HKDF<SHA512>.deriveKey(inputKeyMaterial: key, salt: Data("Pair-Setup-Accessory-Sign-Salt".utf8), info: Data("Pair-Setup-Accessory-Sign-Info".utf8), outputByteCount: 32).withUnsafeBytes { Array($0) }
        let pub = try Curve25519.Signing.PublicKey(rawRepresentation: Data(hostPub))
        XCTCheck(pub.isValidSignature(Data(sig), for: Data(accessoryX + Array(hostID.utf8) + hostPub)), "M6 signature verifies with the host key")
        let hostInfo = try OPACK.decode(PairingTLV.joined(ident, .info))
        XCTCheck(hostInfo["name"]?.stringValue == "Porthole" && hostInfo["accountID"]?.stringValue == hostID, "M6 info says who we are")
        note = hostID
    } catch { note = "phone error: \(error)" }
    return (await hostTask.value, note)
}

let sem = DispatchSemaphore(value: 0)
Task {
    let good = await conversation(pinToType: nil)
    switch good.hostResult {
    case .success(let r):
        check(true, "host finished pairing with \(r.deviceName) (\(r.deviceModel))")
        let plist = try! PropertyListSerialization.propertyList(from: r.pairingFile, options: [], format: nil) as! [String: Any]
        let pub = plist["public_key"] as! Data, priv = plist["private_key"] as! Data
        check(pub.count == 32 && priv.count == 32 && (plist["identifier"] as? String) == good.note, "pairing file has keys and identifier")
        check((try? Curve25519.Signing.PrivateKey(rawRepresentation: priv).publicKey.rawRepresentation) == pub, "private and public key belong together")
        check((plist["alt_irk"] as? Data) == Data(repeating: 0xAB, count: 16), "pairing file keeps the device's altIRK")
        // the same check the app uses when importing
        check((try? JITPairing.validate(r.pairingFile)) != nil, "file passes the app's own pairing-file check (JITPairing.validate)")
    case .failure(let e): check(false, "host failed: \(e) \(good.note)")
    }
    let bad = await conversation(pinToType: "000000")
    switch bad.hostResult {
    case .failure(let e): check((e as? PairingError).map { if case .wrongPIN = $0 { true } else { false } } ?? false && bad.note.contains("code was wrong"), "wrong PIN is rejected and the host reports it (\(bad.note))")
    case .success: check(false, "wrong PIN was accepted")
    }
    print(failures == 0 ? "ALL PASSED" : "\(failures) FAILURE(S)")
    sem.signal()
}
sem.wait()
exit(failures == 0 ? 0 : 1)
