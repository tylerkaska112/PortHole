// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// The little bit of ASN.1 DER that code signing needs: writing a CMS signature, reading a certificate's issuer and serial.
enum DER {
    static func length(_ count: Int) -> Data {
        if count < 0x80 { return Data([UInt8(count)]) }
        var bytes: [UInt8] = []
        var value = count
        while value > 0 { bytes.insert(UInt8(value & 0xff), at: 0); value >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        out.append(length(content.count))
        out.append(content)
        return out
    }

    static func sequence(_ parts: Data...) -> Data { tlv(0x30, parts.reduce(Data(), +)) }
    static func sequence(_ parts: [Data]) -> Data { tlv(0x30, parts.reduce(Data(), +)) }
    static func set(_ parts: [Data]) -> Data { tlv(0x31, parts.reduce(Data(), +)) }
    static func octetString(_ data: Data) -> Data { tlv(0x04, data) }
    static func utf8(_ text: String) -> Data { tlv(0x0c, Data(text.utf8)) }
    static func boolean(_ value: Bool) -> Data { tlv(0x01, Data([value ? 0xff : 0x00])) }
    static let null = Data([0x05, 0x00])

    static func integer(_ value: Int) -> Data {
        var bytes: [UInt8] = []
        var v = value
        repeat { bytes.insert(UInt8(v & 0xff), at: 0); v >>= 8 } while v > 0
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return tlv(0x02, Data(bytes))
    }

    /// `1.2.840.113549.1.7.2` → its DER form.
    static func oid(_ dotted: String) -> Data {
        let arcs = dotted.split(separator: ".").compactMap { UInt64($0) }
        precondition(arcs.count >= 2, "an OID needs two arcs")
        var body: [UInt8] = [UInt8(arcs[0] * 40 + arcs[1])]
        for arc in arcs.dropFirst(2) {
            var chunk: [UInt8] = [UInt8(arc & 0x7f)]
            var rest = arc >> 7
            while rest > 0 { chunk.insert(UInt8(rest & 0x7f) | 0x80, at: 0); rest >>= 7 }
            body += chunk
        }
        return tlv(0x06, Data(body))
    }
}

/// One parsed DER element.
struct DERElement {
    let tag: UInt8
    /// The whole element: tag, length and content.
    let raw: Data
    let content: Data

    var children: [DERElement] { DERParser.elements(in: content) }
}

enum DERParser {
    /// The elements laid end to end in `data` (stops quietly at anything malformed).
    static func elements(in data: Data) -> [DERElement] {
        let bytes = [UInt8](data)
        var result: [DERElement] = []
        var index = 0
        while index < bytes.count {
            guard let (element, next) = element(in: bytes, at: index) else { break }
            result.append(element)
            index = next
        }
        return result
    }

    private static func element(in bytes: [UInt8], at start: Int) -> (DERElement, Int)? {
        guard start + 2 <= bytes.count else { return nil }
        let tag = bytes[start]
        var index = start + 1
        var length = Int(bytes[index]); index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7f
            guard count > 0, count <= 4, index + count <= bytes.count else { return nil }
            length = 0
            for _ in 0..<count { length = length << 8 | Int(bytes[index]); index += 1 }
        }
        guard index + length <= bytes.count else { return nil }
        let element = DERElement(tag: tag, raw: Data(bytes[start..<index + length]), content: Data(bytes[index..<index + length]))
        return (element, index + length)
    }
}

/// The parts of an X.509 certificate that code signing needs.
struct CertificateFields {
    /// The certificate's issuer name, exactly as encoded in the certificate.
    let issuer: Data
    /// The serial number as a complete DER INTEGER.
    let serial: Data
    let notBefore: Date?
    let notAfter: Date?
    /// Where the issuing certificate can be downloaded (the "CA Issuers" access location), if the certificate says.
    let issuerURL: URL?
    var isSelfIssued: Bool { subject == issuer }
    let subject: Data

    init?(der: Data) {
        guard let certificate = DERParser.elements(in: der).first, certificate.tag == 0x30,
              let tbs = certificate.children.first, tbs.tag == 0x30 else { return nil }
        var fields = tbs.children[...]
        if fields.first?.tag == 0xa0 { fields = fields.dropFirst() }   // [0] version
        guard fields.count >= 5 else { return nil }
        let items = Array(fields)
        serial = items[0].raw
        issuer = items[2].raw
        let validity = items[3].children
        notBefore = validity.first.flatMap(Self.date)
        notAfter = validity.count > 1 ? Self.date(validity[1]) : nil
        subject = items[4].raw
        issuerURL = Self.caIssuersURL(in: der)
    }

    private static func date(_ element: DERElement) -> Date? {
        guard let text = String(data: element.content, encoding: .ascii) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = element.tag == 0x17 ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
        return formatter.date(from: text)
    }

    /// AccessDescription { caIssuers (1.3.6.1.5.5.7.48.2), uniformResourceIdentifier [6] "https://…" }
    private static func caIssuersURL(in der: Data) -> URL? {
        let marker: [UInt8] = [0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x30, 0x02, 0x86]
        let bytes = [UInt8](der)
        guard bytes.count > marker.count + 2 else { return nil }
        for start in 0...(bytes.count - marker.count - 1) where Array(bytes[start..<start + marker.count]) == marker {
            let length = Int(bytes[start + marker.count])
            let from = start + marker.count + 1
            guard length < 0x80, from + length <= bytes.count else { continue }
            if let text = String(bytes: bytes[from..<from + length], encoding: .ascii), let url = URL(string: text) { return url }
        }
        return nil
    }
}
