// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// How JIT gets switched on when a game starts. The app's own tunnel serves all three (it stands in for LocalDevVPN).
enum JITMethod: String, CaseIterable, Identifiable {
    case inApp      // this app, with a pairing file made once on a computer
    case stikDebug  // the StikDebug app, opened by this app each time
    case other      // any other tool (SideStore, Jitterbug, a computer...): the person turns JIT on, the app waits for it

    var id: String { rawValue }

    static let key = "f4.jitMethod"

    /// The chosen method. Before anyone chose: in-app when a pairing file exists, otherwise StikDebug (what the app did before this choice existed).
    static var current: JITMethod {
        get {
            // An install without the JIT helper extension cannot do it itself, whatever was chosen before the extension was removed.
            if let raw = UserDefaults.standard.string(forKey: key), let m = JITMethod(rawValue: raw) {
                return m == .inApp && !InstallCheck.hasJITHelper ? .stikDebug : m
            }
            return BuiltinJIT.hasPairing && InstallCheck.hasJITHelper ? .inApp : .stikDebug
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// The methods this install can use: without the JIT helper extension, Porthole cannot switch JIT on itself.
    static var available: [JITMethod] { allCases.filter { $0 != .inApp || InstallCheck.hasJITHelper } }

    var title: String {
        switch self {
        case .inApp: "Porthole does it (recommended)"
        case .stikDebug: "Use the StikDebug app"
        case .other: "I'll use another tool"
        }
    }

    var summary: String {
        switch self {
        case .inApp: "Porthole switches it on by itself every time you press Play. It needs a small \u{201C}pairing file\u{201D}, a one-time step that lets this device trust itself."
        case .stikDebug: "When you press Play, Porthole opens the StikDebug app, which switches it on, and brings you back. You need StikDebug installed."
        case .other: "You switch it on yourself with a tool you already use (SideStore, Jitterbug, a computer\u{2026}). Porthole waits until it sees that it is on."
        }
    }

    var pros: String {
        switch self {
        case .inApp: "Fully automatic: one tap to play, no other app."
        case .stikDebug: "No computer needed once StikDebug is set up."
        case .other: "Works with whatever you already have."
        }
    }

    var cons: String {
        switch self {
        case .inApp: "The pairing file takes a minute to make once (on a computer, unless your device runs iOS 27 or later)."
        case .stikDebug: "A second app to install and keep working; the screen flips to StikDebug and back at every start."
        case .other: "An extra step every time you start a game."
        }
    }
}
