// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

enum SteamVDF {
    /// Parses `"key" "value"` and `"key" { … }` into nested dictionaries. Keys are compared case-insensitively by
    /// lowercasing them. Returns nil for text that is not in the format.
    static func parse(_ text: String) -> [String: Any]? {
        var tokens: [String] = []                 // "{" and "}" are their own tokens; quoted strings come with a leading quote mark
        var scalars = Array(text.unicodeScalars)[...]
        while let c = scalars.first {
            if c == " " || c == "\t" || c == "\r" || c == "\n" || c == "\u{FEFF}" { scalars = scalars.dropFirst(); continue }
            if c == "/", scalars.dropFirst().first == "/" {              // comment to the end of the line
                while let d = scalars.first, d != "\n" { scalars = scalars.dropFirst() }
                continue
            }
            if c == "{" { tokens.append("{"); scalars = scalars.dropFirst(); continue }
            if c == "}" { tokens.append("}"); scalars = scalars.dropFirst(); continue }
            if c == "\"" {
                scalars = scalars.dropFirst()
                var value = String.UnicodeScalarView()
                var closed = false
                while let d = scalars.first {
                    scalars = scalars.dropFirst()
                    if d == "\"" { closed = true; break }
                    if d == "\\", let e = scalars.first {
                        scalars = scalars.dropFirst()
                        switch e { case "n": value.append("\n"); case "t": value.append("\t"); default: value.append(e) }
                        continue
                    }
                    value.append(d)
                }
                if !closed { return nil }
                tokens.append("\"" + String(value)); continue
            }
            return nil                             // an unquoted word: not what Steam writes
        }
        var index = 0
        func object() -> [String: Any]? {
            var result: [String: Any] = [:]
            while index < tokens.count {
                let key = tokens[index]
                if key == "}" { return result }
                guard key.hasPrefix("\""), index + 1 < tokens.count else { return nil }
                let name = String(key.dropFirst()).lowercased()
                let next = tokens[index + 1]
                if next == "{" {
                    index += 2
                    guard let child = object(), index < tokens.count, tokens[index] == "}" else { return nil }
                    index += 1; result[name] = child
                } else if next.hasPrefix("\"") { result[name] = String(next.dropFirst()); index += 2 }
                else { return nil }
            }
            return result
        }
        guard let root = object(), index == tokens.count else { return nil }
        return root
    }
}

// MARK: - What is installed

/// A game found in one of Steam's library folders inside the Wine prefix.
