// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import GameController

extension ControllerKind {
    /// The kind of a connected controller.
    static func detect(_ controller: GCController) -> ControllerKind {
        let pad = controller.extendedGamepad
        return classify(productCategory: controller.productCategory, vendorName: controller.vendorName ?? "",
                        dualSenseProfile: pad is GCDualSenseGamepad, dualShockProfile: pad is GCDualShockGamepad, xboxProfile: pad is GCXboxGamepad)
    }

    /// The controller the person is using: the one that was used last, else the first with a full gamepad.
    static func current() -> (kind: ControllerKind, controller: GCController)? {
        let all = GCController.controllers().filter { $0.extendedGamepad != nil }
        guard let c = GCController.current.flatMap({ all.contains($0) ? $0 : nil }) ?? all.first else { return nil }
        return (detect(c), c)
    }
}
