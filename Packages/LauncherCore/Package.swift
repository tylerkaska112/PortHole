// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import PackageDescription

// LauncherCore = everything that is not presentation: the IPA signer, the update catalog and Hub clients, the download → sign →
// upload → install pipeline, the credential vault and the activity log. It has no SwiftUI/UIKit dependency, so `swift test` runs
// on the Mac in seconds. `launcher-sign` is a Mac command-line front end for the same signer (used to test it with Apple's
// `codesign --verify`, and handy on its own).
let package = Package(
    name: "LauncherCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LauncherCore", targets: ["LauncherCore"]),
        .executable(name: "launcher-sign", targets: ["launcher-sign"]),
    ],
    targets: [
        .target(name: "LauncherCore"),
        .executableTarget(name: "launcher-sign", dependencies: ["LauncherCore"]),
        .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"]),
    ],
    swiftLanguageModes: [.v6]
)
