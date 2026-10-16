// Signs and checks Porthole releases (Ed25519). Run with:  swift tools/release_sign.swift <command> ...
//
//   keygen                         makes the signing key (once) and prints the public key
//   public                         prints the public key (base64) to put in PORTHOLE_RELEASE_KEY
//   sign <app> <version> <build> <sha256>        prints the signature (base64) of one release
//   sign-published <updates-folder> <app>        signs every build listed in that folder's versions.json and latest.json
//   verify <app> <version> <build> <sha256> <signature>   exits 0 when the signature is right
//
// The private key lives in ~/.porthole/release-signing.key (mode 0600), never in the repository. Back it up: a build signed with any other key is refused
// by every install that carries this key's public half. The message that is signed is the same one the app checks (ReleaseSignature.swift).
import Foundation
import CryptoKit

let home = FileManager.default.homeDirectoryForCurrentUser
let keyFile = home.appendingPathComponent(".porthole/release-signing.key")

func fail(_ text: String) -> Never { FileHandle.standardError.write(Data((text + "\n").utf8)); exit(1) }

func loadKey() -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOf: keyFile, encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("No signing key at \(keyFile.path). Run: swift tools/release_sign.swift keygen")
    }
    return key
}

func message(_ app: String, _ version: String, _ build: String, _ sha: String) -> Data {
    Data("porthole-release-v1\n\(app)\n\(version)\n\(build)\n\(sha.lowercased())".utf8)
}

func sign(_ key: Curve25519.Signing.PrivateKey, _ app: String, _ version: String, _ build: String, _ sha: String) -> String {
    (try! key.signature(for: message(app, version, build, sha))).base64EncodedString()
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail("usage: release_sign.swift keygen | public | sign | sign-published | verify") }

switch command {
case "keygen":
    if FileManager.default.fileExists(atPath: keyFile.path) { fail("A key already exists at \(keyFile.path); not replacing it.") }
    try? FileManager.default.createDirectory(at: keyFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let key = Curve25519.Signing.PrivateKey()
    try! Data(key.rawRepresentation.base64EncodedString().utf8).write(to: keyFile, options: .atomic)
    try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    print(loadKey().publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard args.count == 5 else { fail("sign <app> <version> <build> <sha256>") }
    print(sign(loadKey(), args[1], args[2], args[3], args[4]))
case "verify":
    guard args.count == 6, let sig = Data(base64Encoded: args[5]) else { fail("verify <app> <version> <build> <sha256> <signature>") }
    exit(loadKey().publicKey.isValidSignature(sig, for: message(args[1], args[2], args[3], args[4])) ? 0 : 2)
case "sign-published":
    guard args.count == 3 else { fail("sign-published <updates-folder> <app>") }
    let folder = URL(fileURLWithPath: (args[1] as NSString).expandingTildeInPath), app = args[2]
    let key = loadKey()
    func update(_ name: String) -> Int {
        let url = folder.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) else { return 0 }
        var count = 0
        func signed(_ entry: [String: Any]) -> [String: Any] {
            var e = entry
            guard let version = e["version"] as? String, let sha = e["sha256"] as? String else { return e }
            let build = (e["build"] as? String) ?? (e["build"] as? Int).map(String.init) ?? "0"
            e["signature"] = sign(key, app, version, build, sha)
            count += 1
            return e
        }
        let output: Any
        if let list = json as? [[String: Any]] { output = list.map(signed) }
        else if let one = json as? [String: Any] { output = signed(one) }
        else { return 0 }
        let out = try! JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        try! out.write(to: url.appendingPathExtension("tmp"), options: .atomic)
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: url.appendingPathExtension("tmp"))
        return count
    }
    print("signed \(update("versions.json")) release(s) in versions.json and \(update("latest.json")) in latest.json")
default:
    fail("unknown command \(command)")
}
