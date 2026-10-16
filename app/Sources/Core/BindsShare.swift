// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

// Shared bind sets: what the Hub sends and receives (hub/binds.js). Foundation only, so it can be tested on its own.

/// One shared bind set as the Hub shows it. `name` and `notes` are nil until you (the Hub's owner) have approved what the author typed; `pad` and `touch` are
/// only in the full copy, not in lists. The touch controls carry plain labels (E, Space, LMB) until the author's own labels are approved.
struct SharedBind: Codable, Identifiable, Equatable {
    var id: Int
    var gameId: String
    var name: String?
    var notes: String?
    var hasPad: Bool
    var hasTouch: Bool
    var controlCount: Int
    var bindCount: Int
    var look: Bool
    var up: Int
    var down: Int
    var downloads: Int
    var version: Int
    var updated: String
    var pad: PadPart?
    var touch: TouchLayout?

    /// What to call it when the author's name has not been approved (yet).
    var displayName: String { name ?? "Shared set #\(id)" }

    var contents: String {
        var parts: [String] = []
        if hasPad { parts.append(bindCount == 0 ? "Controller (standard buttons)" : "Controller: \(bindCount) changed") }
        if hasTouch { parts.append("Touch layout: \(controlCount) controls" + (look ? ", look" : "")) }
        return parts.isEmpty ? "Empty" : parts.joined(separator: " \u{00B7} ")
    }

    /// Thumbs up as a share of all thumbs, nil until anyone has voted.
    var approval: Double? { up + down == 0 ? nil : Double(up) / Double(up + down) }
}

/// This install's own shared set, with the state of its text.
struct MySharedBind: Codable, Identifiable, Equatable {
    var id: Int
    var clientId: String
    var gameId: String
    var gameTitle: String?
    var textStatus: String          // none, pending, approved, rejected
    var hidden: Bool
    var up: Int
    var down: Int
    var downloads: Int
    var version: Int

    var statusText: String {
        if hidden { return "Hidden (flagged by others)" }
        switch textStatus {
        case "pending": return "Name and notes waiting for approval"
        case "rejected": return "Text was not approved; the set shows without it"
        default: return "Shared"
        }
    }
}

struct SharedBindReview: Codable, Identifiable, Equatable {
    var id: Int
    var thumb: String               // up or down
    var comment: String
    var date: String
}

struct BindPublishResult: Codable, Equatable { var id: Int; var replaced: Bool; var textStatus: String }
struct BindReviewResult: Codable, Equatable { var replaced: Bool; var commentStatus: String; var up: Int; var down: Int }

/// The game a set is for, as the Hub names it (the same references compatibility reports use).
struct BindGameRef: Codable, Equatable {
    var kind: String                // "steam" or "file"
    var steamAppID: Int?
    var fingerprint: String?
    var title: String
}

/// What is sent to publish a set. The set's own ids and dates are not sent; its id (as `clientId`) lets this install replace its own copy.
struct BindPublishPayload: Codable, Equatable {
    var game: BindGameRef
    var clientId: String
    var name: String
    var notes: String
    var pad: PadPart?
    var touch: TouchLayout?

    init(set: BindSet, game: BindGameRef) {
        self.game = game
        clientId = set.id.uuidString.lowercased()
        name = set.name
        notes = set.notes
        pad = set.pad?.sanitized()
        touch = set.touch?.sanitized()
    }
}

enum BindsShare {
    /// A downloaded set becomes an ordinary local set in this game's list. Everything from the Hub is checked again here; it is never put in use by itself.
    static func localSet(from shared: SharedBind, existingNames: [String]) -> BindSet? {
        let pad = shared.pad?.sanitized(), touch = shared.touch?.sanitized()
        guard pad != nil || touch != nil else { return nil }
        var name = BindSetFile.clean(shared.displayName, 40)
        if name.isEmpty { name = "Shared set" }
        var unique = name, n = 2
        while existingNames.contains(unique) { unique = "\(name) \(n)"; n += 1 }
        var set = BindSet(name: unique, notes: BindSetFile.clean(shared.notes ?? "", 300), pad: pad, touch: touch)
        set.downloadedFrom = shared.id
        return set
    }

    /// Why a set can not be shared yet, or nil when it can.
    static func problem(sharing set: BindSet) -> String? {
        if set.pad == nil && set.touch == nil { return "This set has nothing in it. Add controller binds or a touch layout first." }
        if let touch = set.touch, touch.controls.isEmpty, set.pad == nil { return "The touch layout has no controls yet." }
        return nil
    }
}
