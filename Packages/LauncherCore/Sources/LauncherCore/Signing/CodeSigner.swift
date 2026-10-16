// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import CryptoKit

/// What goes into one executable's code signature besides the executable itself.
struct CodeSignatureInputs {
    var identifier: String
    var teamID: String?
    /// Hash of `Info.plist` and of `_CodeSignature/CodeResources` (`nil` for a bare executable without a bundle).
    var infoPlist: Data?
    var codeResources: Data?
    var entitlements: [String: Any]?
    /// `nil` = ad-hoc (no certificate): enough for the Mac to verify the structure, useless on a device.
    var identity: SigningIdentity?
    var isMainExecutable = true
}

/// Writes the code signature into a Mach-O executable — the same structure Apple's `codesign` produces:
/// a SuperBlob holding a SHA-256 CodeDirectory, requirements, entitlements (XML and DER) and the CMS signature.
enum CodeSigner {
    static let pageSizeLog2 = 12
    static let pageSize = 1 << pageSizeLog2

    static func sign(executable: Data, inputs: CodeSignatureInputs) throws -> Data {
        var image = try MachOImage(executable)
        // Start from the executable without any signature it already carries (the linker adds an ad-hoc one).
        let base = image.bytesWithoutSignature()
        let signatureOffset = (base.count + 15) & ~15
        image.bytes = base + [UInt8](repeating: 0, count: signatureOffset - base.count)

        let requirements = emptyRequirements
        let entitlementsXML = try inputs.entitlements.map(entitlementsBlob)
        let entitlementsDER = inputs.entitlements.map(EntitlementsDER.blob)
        let specials = specialSlots(inputs: inputs, requirements: requirements, xml: entitlementsXML, der: entitlementsDER)

        let pageCount = (signatureOffset + pageSize - 1) / pageSize
        let plan = CodeDirectory(
            identifier: inputs.identifier, teamID: inputs.teamID, specials: specials, adhoc: inputs.identity == nil,
            execSegBase: image.textFileOffset, execSegLimit: image.textFileSize,
            execSegFlags: inputs.isMainExecutable && image.isExecutable ? (isDebuggable(inputs.entitlements) ? 0x21 : 0x01) : 0,
            codeLimit: signatureOffset
        )

        // The signature's size must be known before the executable is hashed (the header records it), so measure it with
        // placeholder hashes first: sizes don't depend on hash values.
        let placeholder = plan.build(pageHashes: Array(repeating: Data(count: 32), count: pageCount))
        let cmsPlaceholder = try inputs.identity.map { try CMS.signature(over: placeholder, identity: $0) }
        let layout = SuperBlob.layout(
            codeDirectory: placeholder.count, requirements: requirements.count, entitlementsXML: entitlementsXML?.count,
            entitlementsDER: entitlementsDER?.count, cms: cmsPlaceholder.map { $0.count + 8 } ?? 8
        )
        try image.reserveSignature(offset: signatureOffset, size: layout.total)

        var hashes: [Data] = []
        hashes.reserveCapacity(pageCount)
        var position = 0
        while position < signatureOffset {
            let end = min(position + pageSize, signatureOffset)
            hashes.append(Data(SHA256.hash(data: image.bytes[position..<end])))
            position = end
        }
        let codeDirectory = plan.build(pageHashes: hashes)
        var cmsBlob = Data()
        cmsBlob.be32(0xfade0b01)
        if let identity = inputs.identity {
            let cms = try CMS.signature(over: codeDirectory, identity: identity)
            guard cms.count + 8 <= layout.cms else { throw SigningError.signingFailed("the signature grew unexpectedly") }
            cmsBlob.be32(UInt32(cms.count + 8)); cmsBlob.append(cms)
        } else {
            cmsBlob.be32(8)
        }
        let blob = SuperBlob.assemble(
            codeDirectory: codeDirectory, requirements: requirements, entitlementsXML: entitlementsXML, entitlementsDER: entitlementsDER, cms: cmsBlob
        )
        precondition(blob.count == layout.total, "signature size changed after measuring")
        return Data(image.bytes) + blob
    }

    // MARK: Pieces

    /// A requirements blob with no requirements (what `codesign` writes for an ad-hoc signature).
    static let emptyRequirements: Data = {
        var blob = Data()
        blob.be32(0xfade0c01); blob.be32(12); blob.be32(0)
        return blob
    }()

    static func entitlementsBlob(_ entitlements: [String: Any]) throws -> Data {
        let xml = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
        var blob = Data()
        blob.be32(0xfade7171); blob.be32(UInt32(xml.count + 8)); blob.append(xml)
        return blob
    }

    private static func isDebuggable(_ entitlements: [String: Any]?) -> Bool { entitlements?["get-task-allow"] as? Bool ?? false }

    /// Hashes of the "special" slots, index 0 = slot −1 (Info.plist), 1 = −2 (requirements), 2 = −3 (CodeResources), 4 = −5
    /// (entitlements), 6 = −7 (DER entitlements). Slots this signature doesn't use are all zeros.
    private static func specialSlots(inputs: CodeSignatureInputs, requirements: Data, xml: Data?, der: Data?) -> [Data] {
        let zero = Data(count: 32)
        func hash(_ data: Data?) -> Data { data.map { Data(SHA256.hash(data: $0)) } ?? zero }
        var slots = [hash(inputs.infoPlist), hash(requirements), hash(inputs.codeResources), zero, hash(xml), zero, hash(der)]
        if der == nil { slots.removeLast(2) }
        if xml == nil { slots.removeLast(2) }
        return slots
    }
}

// MARK: - CodeDirectory

struct CodeDirectory {
    var identifier: String
    var teamID: String?
    var specials: [Data]
    var adhoc: Bool
    var execSegBase: UInt64
    var execSegLimit: UInt64
    var execSegFlags: UInt64
    var codeLimit: Int

    func build(pageHashes: [Data]) -> Data {
        let identifierBytes = Data(identifier.utf8) + Data([0])
        let teamBytes = teamID.map { Data($0.utf8) + Data([0]) }
        let headerSize = 88
        let teamOffset = teamBytes == nil ? 0 : headerSize + identifierBytes.count
        let hashesStart = headerSize + identifierBytes.count + (teamBytes?.count ?? 0)
        let hashOffset = hashesStart + specials.count * 32

        var d = Data()
        d.be32(0xfade0c02)
        d.be32(0)                                   // length, patched below
        d.be32(0x20400)                             // version: exec-segment fields, no scatter
        d.be32(adhoc ? 2 : 0)                       // flags
        d.be32(UInt32(hashOffset))
        d.be32(UInt32(headerSize))                  // identifier offset
        d.be32(UInt32(specials.count))
        d.be32(UInt32(pageHashes.count))
        d.be32(UInt32(codeLimit))
        d.append(contentsOf: [32, 2, 0, UInt8(CodeSigner.pageSizeLog2)])   // hash size, SHA-256, platform, page size
        d.be32(0)                                   // spare
        d.be32(0)                                   // scatter offset
        d.be32(UInt32(teamOffset))
        d.be32(0)                                   // spare
        d.be64(0)                                   // 64-bit code limit (unused below 4 GB)
        d.be64(execSegBase)
        d.be64(execSegLimit)
        d.be64(execSegFlags)
        d.append(identifierBytes)
        if let teamBytes { d.append(teamBytes) }
        for slot in specials.reversed() { d.append(slot) }
        for hash in pageHashes { d.append(hash) }
        let length = UInt32(d.count)
        d.replaceSubrange(4..<8, with: [UInt8(length >> 24), UInt8(length >> 16 & 0xff), UInt8(length >> 8 & 0xff), UInt8(length & 0xff)])
        return d
    }
}

// MARK: - SuperBlob

enum SuperBlob {
    struct Layout { var total: Int; var cms: Int }

    private static func slots(cd: Int, req: Int, xml: Int?, der: Int?, cms: Int) -> [(type: UInt32, size: Int)] {
        var slots: [(UInt32, Int)] = [(0, cd), (2, req)]
        if let xml { slots.append((5, xml)) }
        if let der { slots.append((7, der)) }
        slots.append((0x10000, cms))
        return slots
    }

    static func layout(codeDirectory: Int, requirements: Int, entitlementsXML: Int?, entitlementsDER: Int?, cms: Int) -> Layout {
        let all = slots(cd: codeDirectory, req: requirements, xml: entitlementsXML, der: entitlementsDER, cms: cms)
        return Layout(total: 12 + all.count * 8 + all.reduce(0) { $0 + $1.size }, cms: cms)
    }

    static func assemble(codeDirectory: Data, requirements: Data, entitlementsXML: Data?, entitlementsDER: Data?, cms: Data) -> Data {
        var blobs: [(UInt32, Data)] = [(0, codeDirectory), (2, requirements)]
        if let entitlementsXML { blobs.append((5, entitlementsXML)) }
        if let entitlementsDER { blobs.append((7, entitlementsDER)) }
        blobs.append((0x10000, cms))
        var out = Data()
        out.be32(0xfade0cc0)
        out.be32(UInt32(12 + blobs.count * 8 + blobs.reduce(0) { $0 + $1.1.count }))
        out.be32(UInt32(blobs.count))
        var offset = 12 + blobs.count * 8
        for (type, blob) in blobs { out.be32(type); out.be32(UInt32(offset)); offset += blob.count }
        for (_, blob) in blobs { out.append(blob) }
        return out
    }
}

// MARK: - Entitlements as DER

/// The DER form of an entitlements dictionary that iOS 15+ expects next to the XML one.
enum EntitlementsDER {
    static func blob(_ entitlements: [String: Any]) -> Data {
        let body = DER.tlv(0x70, DER.integer(1) + dictionary(entitlements))
        var blob = Data()
        blob.be32(0xfade7172); blob.be32(UInt32(body.count + 8)); blob.append(body)
        return blob
    }

    private static func dictionary(_ dictionary: [String: Any]) -> Data {
        let entries = dictionary.keys.sorted().map { DER.sequence(DER.utf8($0), value(dictionary[$0]!)) }
        return DER.tlv(0xb0, entries.reduce(Data(), +))
    }

    private static func value(_ value: Any) -> Data {
        switch value {
        case let text as String: return DER.utf8(text)
        case let dict as [String: Any]: return dictionary(dict)
        case let array as [Any]: return DER.sequence(array.map(Self.value))
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return DER.boolean(number.boolValue) }
            return DER.integer(number.intValue)
        default: return DER.utf8("\(value)")
        }
    }
}

// MARK: - CMS signature

/// The detached CMS SignedData Apple's signatures carry: it signs the CodeDirectory's hash and lists the certificates.
enum CMS {
    static func signature(over codeDirectory: Data, identity: SigningIdentity) throws -> Data {
        guard let leaf = CertificateFields(der: identity.leafDER) else { throw SigningError.badCertificateFile("unreadable certificate") }
        let hash = Data(SHA256.hash(data: codeDirectory))
        let sha256 = DER.sequence(DER.oid("2.16.840.1.101.3.4.2.1"))

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>cdhashes</key>
        \t<array>
        \t\t<data>
        \t\t\(hash.prefix(20).base64EncodedString())
        \t\t</data>
        \t</array>
        </dict>
        </plist>

        """
        func attribute(_ oid: String, _ value: Data) -> Data { DER.sequence(DER.oid(oid), DER.set([value])) }
        let attributes = [
            attribute("1.2.840.113549.1.9.3", DER.oid("1.2.840.113549.1.7.1")),
            attribute("1.2.840.113549.1.9.4", DER.octetString(hash)),
            attribute("1.2.840.113635.100.9.2", DER.sequence(DER.oid("2.16.840.1.101.3.4.2.1"), DER.octetString(hash))),
            attribute("1.2.840.113635.100.9.1", DER.octetString(Data(plist.utf8))),
        ].reduce(Data(), +)

        // The signature covers the attributes encoded as a SET.
        let signature = try identity.sign(DER.tlv(0x31, attributes))
        let signer = DER.sequence(
            DER.integer(1),
            DER.sequence(leaf.issuer, leaf.serial),
            sha256,
            DER.tlv(0xa0, attributes),
            DER.sequence(DER.oid("1.2.840.113549.1.1.11"), DER.null),
            DER.octetString(signature)
        )
        let signedData = DER.sequence(
            DER.integer(1),
            DER.set([sha256]),
            DER.sequence(DER.oid("1.2.840.113549.1.7.1")),
            DER.tlv(0xa0, identity.chain.reduce(Data(), +)),
            DER.set([signer])
        )
        return DER.sequence(DER.oid("1.2.840.113549.1.7.2"), DER.tlv(0xa0, signedData))
    }
}
