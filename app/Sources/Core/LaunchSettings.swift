// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import UIKit

/// The settings a launch actually uses: the game's own override where it has one, else the global setting.
@MainActor
struct LaunchSettings {
    var power: PowerMode
    var keepModeWhenHot: Bool
    var swapMB: Int
    var swapCoverage: String
    var vramMB: Int
    var audioCushionMs: Int
    var preciseMath: Bool
    var dockDesktop: Bool
    var lookSensitivity: Double
    var resolution: String            // DisplayResolution id

    static let defaultLookSensitivity = 2.4, lookRange = 0.4...8.0
    static var globalLookSensitivity: Double {
        get { (UserDefaults.standard.object(forKey: "f4.lookSensitivity") as? Double) ?? defaultLookSensitivity }
        set { UserDefaults.standard.set(newValue, forKey: "f4.lookSensitivity") }
    }

    // MARK: Resolution

    static let resolutionKey = "f4.resolution"
    static var globalResolution: String {
        get { DisplayResolution.offered(UserDefaults.standard.string(forKey: resolutionKey)) ?? DisplayResolution.defaultID }
        set { UserDefaults.standard.set(newValue, forKey: resolutionKey) }
    }
    /// Width / height of this device's screen in landscape, for the "screen shape" sizes.
    static var screenAspect: Double {
        let b = UIScreen.main.bounds
        let w = max(b.width, b.height), h = min(b.width, b.height)
        return h > 0 ? Double(w / h) : 16.0 / 9.0
    }
    /// The size of the virtual screen this launch uses.
    var displaySize: DisplayResolution { DisplayResolution.resolve(id: resolution, screenAspect: Self.screenAspect) }

    // MARK: Global values (UserDefaults; swap and video memory used to live only in madeira.cfg, which is now written at launch from these)

    enum Key {
        static let swapMB = "f4.swapMB", swapCoverage = "f4.swapCoverage", vramMB = "f4.vramMB"
    }

    static var globalSwapMB: Int {
        get { (UserDefaults.standard.object(forKey: Key.swapMB) as? Int) ?? Int(MadeiraConfig.get("swap-mb") ?? "") ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: Key.swapMB) }
    }
    static var globalSwapCoverage: String {
        get {
            if let v = UserDefaults.standard.string(forKey: Key.swapCoverage) { return v }
            let v = (MadeiraConfig.get("env.MADEIRA_SWAP_COVERAGE") ?? "").lowercased()
            if v.isEmpty, MadeiraConfig.get("swap-mode") == "2" { return "broad" }   // the old Engine options row; see EngineOptions.migrateSwapMode()
            return v == "classic" ? "" : v
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.swapCoverage) }
    }
    static var globalVramMB: Int {
        get { (UserDefaults.standard.object(forKey: Key.vramMB) as? Int) ?? Int(MadeiraConfig.get("vram-mb") ?? "") ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: Key.vramMB) }
    }

    static func resolve(for game: Game?) -> LaunchSettings {
        let o = game?.settings ?? GameSettings()
        return LaunchSettings(
            power: o.powerMode.flatMap(PowerMode.init(rawValue:)) ?? PowerManager.shared.userMode,
            keepModeWhenHot: o.keepModeWhenHot ?? PowerManager.shared.ignoreHeat,
            swapMB: o.swapMB ?? globalSwapMB,
            swapCoverage: o.swapCoverage ?? globalSwapCoverage,
            vramMB: o.vramMB ?? globalVramMB,
            audioCushionMs: o.audioCushionMs ?? SessionController.audioCushionMs,
            preciseMath: o.preciseMath ?? SessionController.preciseMath,
            dockDesktop: o.dockDesktop ?? SessionController.dockDesktop,
            lookSensitivity: o.lookSensitivity ?? globalLookSensitivity,
            resolution: DisplayResolution.offered(o.resolution) ?? globalResolution)
    }

    /// Writes what the runtime reads from madeira.cfg and tells PowerManager what this session uses. Call right before a launch.
    func apply() {
        EngineOptions.migrateSwapMode()
        _ = MadeiraConfig.set("swap-mb", swapMB > 0 ? String(swapMB) : nil)
        _ = MadeiraConfig.set("env.MADEIRA_SWAP_COVERAGE", swapMB > 0 && !swapCoverage.isEmpty ? swapCoverage : nil)
        _ = MadeiraConfig.set("vram-mb", vramMB > 0 ? String(vramMB) : nil)
        PowerManager.shared.beginSession(mode: power, keepWhenHot: keepModeWhenHot)
        LogStore.shared.log("[settings] launch: power=\(power.title) keepHot=\(keepModeWhenHot) swap=\(swapMB)MB/\(swapCoverage.isEmpty ? "classic" : swapCoverage) vram=\(vramMB) audio=\(audioCushionMs)ms precise=\(preciseMath) desktop=\(dockDesktop) resolution=\(displaySize.text)")
    }
}
