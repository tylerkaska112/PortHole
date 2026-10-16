// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Takes out of a log what identifies a person or a device: the random folder names of the app's container, a home folder, account names, e-mail addresses and
/// public IP addresses. Hex fingerprints and everything about the engine stay, because they are what makes a log useful. A log can be tens of megabytes, so a big
/// one is cleaned in pieces of whole lines, and the cheap checks come before the expensive ones.
enum LogCleaner {
    /// For a short text (what a person typed).
    static func clean(_ text: String, accountNames: [String]) -> String {
        cleanPiece(text, names: accountNames)
    }

    /// For a log of any size.
    static func cleanData(_ data: Data, accountNames: [String]) -> Data {
        let piece = 2 * 1024 * 1024
        var out = Data()
        out.reserveCapacity(data.count)
        var start = data.startIndex
        while start < data.endIndex {
            var end = min(start + piece, data.endIndex)
            if end < data.endIndex, let newline = data[start..<end].lastIndex(of: 0x0A) { end = newline + 1 }
            let text = String(decoding: data[start..<end], as: UTF8.self)
            out.append(Data(cleanPiece(text, names: accountNames).utf8))
            start = end
        }
        return out
    }

    private static func replace(_ s: inout String, _ regex: NSRegularExpression?, _ template: String) {
        guard let regex else { return }
        s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    private static let containerPaths = try? NSRegularExpression(pattern: "(/(?:private/)?var/(?:mobile/Containers/Data|containers/Bundle)/Application/)[0-9A-Fa-f-]{36}")
    private static let homePaths = try? NSRegularExpression(pattern: "(/Users/)[^/\\s\"']+")
    private static let emails = try? NSRegularExpression(pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
    /// A Steam account's 64-bit id (it is a public id, but it names the person), Epic's account id and user name on a game's command line.
    private static let steamIDs = try? NSRegularExpression(pattern: "(?<![0-9])7656119[0-9]{10}(?![0-9])")
    private static let epicIDs = try? NSRegularExpression(pattern: "(?i)(epicuserid[=:\\s\"]*)[0-9a-f]{32}")
    private static let epicNamesQuoted = try? NSRegularExpression(pattern: "(?i)(\"[-/]?epicusername[=:])[^\"\\n]*")
    private static let epicNames = try? NSRegularExpression(pattern: "(?i)(epicusername[=:\\s]*)[^\\s\"]+")

    /// A credential on a command line or in a line of text: the value goes, the name stays.
    private static let authPasswords = try? NSRegularExpression(pattern: "(?i)(auth_?password[=:\\s\"]*)[^\\s\"]+")
    private static let namedSecrets = try? NSRegularExpression(pattern: "(?i)(token|api[_-]?key|client[_-]?secret|password)([\"']?\\s*[=:]\\s*[\"']?)[A-Za-z0-9._~+/%-]{12,}")
    private static let ipv6 = try? NSRegularExpression(pattern: "(?i)(?<![0-9a-zA-Z_:.])[0-9a-f:]*::[0-9a-f:]*(?![0-9a-zA-Z_:])")

    /// Public IPv6 addresses (the compressed form with "::", which is how they are printed) become `<ip>`; loopback, link-local and unique-local ones stay.
    static func redactIPv6(_ text: String) -> String {
        guard let ipv6, text.contains("::") else { return text }
        let ns = text as NSString
        var out = "", last = 0
        for match in ipv6.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            let lower = token.lowercased()
            let groups = lower.split(separator: ":", omittingEmptySubsequences: true)
            let valid = groups.count <= 7 && groups.allSatisfy { $0.count <= 4 && $0.allSatisfy(\.isHexDigit) } && lower.components(separatedBy: "::").count == 2
            let local = lower == "::" || lower == "::1" || lower.hasPrefix("fe8") || lower.hasPrefix("fe9") || lower.hasPrefix("fea") || lower.hasPrefix("feb")
                || lower.hasPrefix("fc") || lower.hasPrefix("fd")
            guard valid, !local else { continue }
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last)) + "<ip>"
            last = match.range.location + match.range.length
        }
        return out + ns.substring(from: last)
    }

    private static func cleanPiece(_ text: String, names: [String]) -> String {
        var out = text
        if out.contains("/Containers/") || out.contains("/containers/") { replace(&out, containerPaths, "$1<id>") }
        if out.contains("/Users/") { replace(&out, homePaths, "$1<user>") }
        if out.contains("@") { replace(&out, emails, "<email>") }
        if out.contains("7656119") { replace(&out, steamIDs, "<steamid>") }
        if out.range(of: "epicuserid", options: .caseInsensitive) != nil { replace(&out, epicIDs, "$1<epic-id>") }
        if out.range(of: "epicusername", options: .caseInsensitive) != nil { replace(&out, epicNamesQuoted, "$1<account>"); replace(&out, epicNames, "$1<account>") }
        if out.range(of: "auth_password", options: .caseInsensitive) != nil || out.range(of: "authpassword", options: .caseInsensitive) != nil { replace(&out, authPasswords, "$1<redacted>") }
        if out.range(of: "token", options: .caseInsensitive) != nil || out.range(of: "api", options: .caseInsensitive) != nil || out.range(of: "secret", options: .caseInsensitive) != nil
            || out.range(of: "password", options: .caseInsensitive) != nil { replace(&out, namedSecrets, "$1$2<redacted>") }
        out = redactIPv6(out)
        for name in names where name.count >= 3 {
            if out.range(of: name, options: .caseInsensitive) != nil { out = out.replacingOccurrences(of: name, with: "<account>", options: .caseInsensitive) }
        }
        return String(decoding: redactPublicIPs(Array(out.utf8)), as: UTF8.self)
    }

    // MARK: IP addresses

    private static func isWordByte(_ b: UInt8) -> Bool { (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95 }

    /// Replaces every dotted-quad that is not a private, loopback or link-local address with `<ip>`. A scan of the bytes: no regular expression, so it stays fast on
    /// a log of tens of megabytes.
    static func redactPublicIPs(_ bytes: [UInt8]) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        let n = bytes.count
        var i = 0
        while i < n {
            let b = bytes[i]
            guard b >= 48 && b <= 57, i == 0 || (!isWordByte(bytes[i - 1]) && bytes[i - 1] != 46) else { out.append(b); i += 1; continue }
            // Try d{1,3}.d{1,3}.d{1,3}.d{1,3}
            var j = i
            var groups: [Int] = []
            var ok = true
            for g in 0..<4 {
                var digits = 0, value = 0
                while j < n, bytes[j] >= 48, bytes[j] <= 57, digits < 3 { value = value * 10 + Int(bytes[j] - 48); j += 1; digits += 1 }
                if digits == 0 || value > 255 { ok = false; break }
                groups.append(value)
                if g < 3 { if j < n, bytes[j] == 46 { j += 1 } else { ok = false; break } }
            }
            if ok, j < n, isWordByte(bytes[j]) || (bytes[j] == 46 && j + 1 < n && bytes[j + 1] >= 48 && bytes[j + 1] <= 57) { ok = false }
            guard ok else { out.append(b); i += 1; continue }
            let a = groups[0], c = groups[1]
            let isPrivate = a == 10 || a == 127 || a == 0 || (a == 192 && c == 168) || (a == 172 && (16...31).contains(c)) || (a == 169 && c == 254)
            if isPrivate { out.append(contentsOf: bytes[i..<j]) } else { out.append(contentsOf: Array("<ip>".utf8)) }
            i = j
        }
        return out
    }
}
