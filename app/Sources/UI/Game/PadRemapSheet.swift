// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

/// Which controller button the game sees for each button on the pad, for this game (the modes where the pad reaches the game as a controller). Swap A and B, put a
/// bumper on a trigger, turn a button off. Press the button to change it, or pick it from the list.
struct PadRemapSheet: View {
    let gameID: UUID
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var scope = FocusScope()
    @StateObject private var listener = PadPressListener()
    @State private var picked: String?
    @State private var heardNote: String?

    private var game: Game? { model.games.first { $0.id == gameID } }
    /// The buttons are named the way they are printed on the connected controller (A (✕) on a PlayStation pad).
    private var padKind: ControllerKind { ControllerInput.shared.kind }
    private static let stickNames: Set<String> = ["LS", "RS"]

    var body: some View {
        ZStack {
            AmbientBackdrop(animated: false)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Remap buttons").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text)
                    Spacer()
                    PillButton(id: "pr-close", title: "Done", symbol: "checkmark") { dismiss() }
                }
                .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 8)
                FocusScroll {
                    if let g = game {
                        let map = g.engine?.padRemap ?? [:]
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Which button the game sees when you press each one on the controller. Pick what a button should do instead; to swap two buttons, change both. This works while the controller is an Xbox or DualSense pad for the game, not in keyboard-and-mouse mode (use Controller buttons there). Hold Menu + View for half a second still opens the Porthole menu.")
                                .font(.footnote).foregroundStyle(Theme.textDim).padding(.horizontal, 6)
                            SettingsGroup(title: "Change one by pressing it") {
                                if listener.listening {
                                    ActionRow(id: "pr-listen", symbol: "gamecontroller.fill", title: "Press the button now\u{2026}", subtitle: "Tap here to cancel", chevron: false) { listener.stop() }
                                } else {
                                    ActionRow(id: "pr-press", symbol: "hand.point.up.left.fill", title: "Press a controller button to change it",
                                              subtitle: heardNote ?? "Then pick what the game sees", chevron: false) { listen() }
                                }
                                if let name = picked, PadActions.buttons.contains(name) { row(g, name, map: map, id: "pr-picked", title: "\(padKind.label(name)) acts as") }
                            }
                            SettingsGroup(title: "Buttons") {
                                ForEach(PadActions.buttons, id: \.self) { name in row(g, name, map: map, id: "pr-\(name)", title: padKind.label(name)) }
                            }
                            SettingsGroup(title: "Quick changes") {
                                ActionRow(id: "pr-swapab", symbol: "arrow.left.arrow.right", title: "Swap A and B", subtitle: "Confirm and cancel the other way round", chevron: false) { swap(g, "A", "B") }
                                ActionRow(id: "pr-swapxy", symbol: "arrow.left.arrow.right", title: "Swap X and Y", chevron: false) { swap(g, "X", "Y") }
                                ActionRow(id: "pr-swaptrig", symbol: "arrow.left.arrow.right", title: "Swap the triggers with the bumpers", subtitle: "\(padKind.glyph("LT")) and \(padKind.glyph("RT")) on \(padKind.glyph("LB")) and \(padKind.glyph("RB"))", chevron: false) {
                                    swap(g, "LT", "LB"); swap(g, "RT", "RB")
                                }
                            }
                            if !PadRemap(map: map).isEmpty {
                                ActionRow(id: "pr-reset", symbol: "arrow.counterclockwise", title: "Back to the standard buttons", chevron: false) { clear(g) }
                            }
                        }
                        .frame(maxWidth: 680).frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navScope(scope)
        .onAppear { scope.onBack = { dismiss() }; scope.defaultFocus = "pr-close"; scope.focused = "pr-close" }
        .onDisappear { listener.stop() }
        .presentationBackground(Theme.background)
    }

    private func row(_ g: Game, _ name: String, map: [String: String], id: String, title: String) -> some View {
        ChoiceRow(id: id, symbol: "circle.circle", title: title,
                  options: PadRemap.targets.map { target in (target, target == "none" ? "Nothing" : (target == name ? "\(padKind.label(target)) (standard)" : padKind.label(target))) },
                  selection: Binding(get: { map[name] ?? name }, set: { set(g, name, $0) }))
    }

    private func listen() {
        heardNote = nil
        listener.start { name in
            switch name {
            case "": heardNote = "No controller is connected."
            case "-": heardNote = "Nothing was pressed."
            case "LS", "RS": heardNote = "Sticks cannot be remapped here."
            default:
                picked = name
                heardNote = "You pressed \(name). Pick what the game sees below."
                scope.focus("pr-picked")
            }
        }
    }

    private func set(_ g: Game, _ name: String, _ output: String) {
        model.update(g) {
            var e = $0.engine ?? GameEngine()
            var m = e.padRemap ?? [:]
            if output == name { m.removeValue(forKey: name) } else { m[name] = output }
            e.padRemap = m.isEmpty ? nil : m
            $0.engine = e.isEmpty ? nil : e
        }
    }

    /// Makes `a` act as `b` and `b` as `a`.
    private func swap(_ g: Game, _ a: String, _ b: String) {
        model.update(g) {
            var e = $0.engine ?? GameEngine()
            var m = e.padRemap ?? [:]
            m[a] = b; m[b] = a
            e.padRemap = PadRemap(map: m).isEmpty ? nil : m
            $0.engine = e.isEmpty ? nil : e
        }
    }

    private func clear(_ g: Game) { model.update(g) { var e = $0.engine ?? GameEngine(); e.padRemap = nil; $0.engine = e.isEmpty ? nil : e } }
}
