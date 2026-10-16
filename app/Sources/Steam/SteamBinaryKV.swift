// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
// Valve's binary KeyValues: the format of a package's product information (apps and depots use the text form, see SteamVDF).
import Foundation

enum SteamBinaryKV {
    /// Reads entries until the end marker or the end of the data. Objects become dictionaries; values are String, Int, UInt64 or Double.
    /// Returns nil for data that is not in the format.
    static func parse(_ data: Data) -> [String: Any]? {
        let bytes = Array(data)
        var at = 0
        func cString() -> String? {
            var end = at
            while end < bytes.count, bytes[end] != 0 { end += 1 }
            guard end < bytes.count else { return nil }
            defer { at = end + 1 }
            return String(decoding: bytes[at..<end], as: UTF8.self)
        }
        func wideString() -> String? {
            var units: [UInt16] = []
            while at + 1 < bytes.count {
                let unit = UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
                at += 2
                if unit == 0 { return String(decoding: units, as: UTF16.self) }
                units.append(unit)
            }
            return nil
        }
        func le(_ count: Int) -> UInt64? {
            guard at + count <= bytes.count else { return nil }
            var value: UInt64 = 0
            for i in 0..<count { value |= UInt64(bytes[at + i]) << (8 * UInt64(i)) }
            at += count
            return value
        }
        func object(depth: Int) -> [String: Any]? {
            guard depth < 32 else { return nil }
            var result: [String: Any] = [:]
            while at < bytes.count {
                let type = bytes[at]; at += 1
                if type == 8 { return result }
                guard let name = cString() else { return nil }
                switch type {
                case 0: guard let child = object(depth: depth + 1) else { return nil }; result[name] = child
                case 1: guard let text = cString() else { return nil }; result[name] = text
                case 2, 4, 6: guard let value = le(4) else { return nil }; result[name] = Int(Int32(truncatingIfNeeded: value))
                case 3: guard let value = le(4) else { return nil }; result[name] = Double(Float(bitPattern: UInt32(value)))
                case 5: guard let text = wideString() else { return nil }; result[name] = text
                case 7: guard let value = le(8) else { return nil }; result[name] = value
                case 10: guard let value = le(8) else { return nil }; result[name] = Int(Int64(bitPattern: value))
                default: return nil
                }
            }
            return result
        }
        return object(depth: 0)
    }
}

/// What a package (a purchase or free sub) contains.
struct SteamPackageInfo: Equatable {
    var packageID: Int
    var appIDs: [Int]
    var depotIDs: [Int]

    /// A package's product information: the package id as four bytes, then binary KeyValues named after it.
    static func parse(_ buffer: Data, packageID: Int) -> SteamPackageInfo? {
        guard buffer.count > 4, let root = SteamBinaryKV.parse(buffer.dropFirst(4)) else { return nil }
        let body = (root[String(packageID)] as? [String: Any]) ?? (root.values.first { $0 is [String: Any] } as? [String: Any]) ?? root
        func ids(_ key: String) -> [Int] {
            let list = (body[key] as? [String: Any]) ?? [:]
            return list.compactMap { $0.value as? Int ?? ($0.value as? UInt64).map(Int.init) ?? ($0.value as? String).flatMap(Int.init) }.filter { $0 > 0 }.sorted()
        }
        return SteamPackageInfo(packageID: packageID, appIDs: ids("appids"), depotIDs: ids("depotids"))
    }
}
