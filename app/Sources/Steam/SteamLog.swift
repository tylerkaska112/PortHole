// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// Where the Steam code reports what it is doing. The app points `sink` at its log; tests leave it silent or print.
enum SteamLog {
    nonisolated(unsafe) static var sink: ((String) -> Void)?
    static func event(_ text: String) { sink?(text) }
}
