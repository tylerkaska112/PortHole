// Host tests for the D-pad navigation rules (FocusSpatial.swift) on layouts like the real screens.
import CoreGraphics

// FocusScope asks the app's NavHub whether the pointer may move focus; the tests stand in for it (the D-pad was just used).
@MainActor final class NavHub { static let shared = NavHub(); var pointerMayMoveFocus = false }
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "ok    " : "FAIL  ", what); if !ok { failures += 1 } }

@MainActor func fid(_ s: FocusScope) -> String? { s.focused as? String }
typealias Item = (id: String, frame: CGRect)
func go(_ items: [Item], from: String, _ d: NavDirection, anchor: CGFloat? = nil) -> String? {
    let cur = items.first { $0.id == from }!.frame
    return SpatialFocus.next(from: cur, among: items, direction: d, excluding: from, anchor: anchor)
}
func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }

// --- A grid of game tiles: 5 columns, rows of slightly different heights (titles of one or two lines), the last row short.
var grid: [Item] = []
let colW: CGFloat = 360, gap: CGFloat = 12
for i in 0..<12 {
    let row = i / 5, col = i % 5
    let h: CGFloat = (i % 3 == 1) ? 214 : 200                    // uneven tile heights, as with a one- or two-line caption
    grid.append(("g\(i)", r(CGFloat(col) * (colW + gap), CGFloat(row) * 230, colW, h)))
}
check(go(grid, from: "g1", .down) == "g6", "grid: down from a tile goes to the tile below it, not a neighbour whose centre is a little lower")
check(go(grid, from: "g6", .up) == "g1", "grid: up comes back to the same tile")
check(go(grid, from: "g1", .right) == "g2" && go(grid, from: "g1", .left) == "g0", "grid: left and right go to the neighbours")
check(go(grid, from: "g4", .right) == nil, "grid: right from the last column stays put")
check(go(grid, from: "g11", .down) == nil, "grid: down from the last row stays put")
check(go(grid, from: "g9", .down) == "g11", "grid: down from the end of a full row goes to the nearest tile of the shorter row below")
check(go(grid, from: "g10", .up) == "g5", "grid: up from the short last row goes to the tile above")
// the last row has only two tiles (g10, g11); going down from g4 (column 4) has to land on the nearest one, not nothing
let short = Array(grid.prefix(12))
check(go(short, from: "g4", .down) == "g9", "grid: down from column 4 goes to g9 (its column exists in row 2)")
check(go(short, from: "g8", .down) == "g11", "grid: down from column 3 goes to the nearest tile of a shorter row")

// --- A hero card spanning the screen above the grid: down goes to the tile under the middle of the hero, then up returns to the hero.
var screen: [Item] = [("hero", r(0, 0, 1900, 600))] + grid.map { ($0.id, $0.frame.offsetBy(dx: 0, dy: 700)) }
check(go(screen, from: "hero", .down) == "g2", "hero: down lands on the tile under the hero's centre")
check(go(screen, from: "g0", .up) == "hero" && go(screen, from: "g4", .up) == "hero", "hero: up from any tile of the first row goes to the hero")

// --- A settings list: full-width rows, then a row of two buttons.
var list: [Item] = (0..<6).map { ("row\($0)", r(100, CGFloat($0) * 90, 1200, 80)) }
list.append(("btnA", r(100, 600, 580, 70))); list.append(("btnB", r(700, 600, 600, 70)))
check(go(list, from: "row2", .down) == "row3" && go(list, from: "row3", .up) == "row2", "list: down and up step one row")
check(go(list, from: "row5", .down) == "btnB", "list: down from a full-width row goes to the button whose centre is nearest the row's centre")
check(go(list, from: "btnA", .right) == "btnB" && go(list, from: "btnB", .up) == "row5", "list: buttons: right to the other button, up to the last row")
check(go(list, from: "row0", .right) == nil && go(list, from: "row0", .left) == nil, "list: left and right do nothing on a full-width row")

// --- The sticky column: down through a wide row and back up returns to the same column of the grid.
let mixed: [Item] = [("a", r(0, 0, 300, 100)), ("b", r(320, 0, 300, 100)), ("c", r(640, 0, 300, 100)),
                     ("wide", r(0, 120, 940, 100)),
                     ("d", r(0, 240, 300, 100)), ("e", r(320, 240, 300, 100)), ("f", r(640, 240, 300, 100))]
let down1 = go(mixed, from: "c", .down)                                       // wide
let down2 = go(mixed, from: "wide", .down, anchor: mixed[2].frame.midX)       // with the column remembered: f
let down3 = go(mixed, from: "wide", .down)                                    // without: the middle one
check(down1 == "wide" && down2 == "f", "sticky column: c -> wide -> f keeps the column")
check(down3 == "e", "without the remembered column the tile under the wide row's centre is chosen")

// --- Items a long way off the axis do not steal focus.
let far: [Item] = [("here", r(0, 0, 200, 80)), ("below", r(0, 200, 200, 80)), ("faraway", r(1500, 130, 200, 80))]
check(go(far, from: "here", .down) == "below", "a lined-up item below beats one that is far to the side")
// --- Only item in the direction, even if off to the side.
let side: [Item] = [("here", r(0, 0, 200, 80)), ("other", r(900, 300, 200, 80))]
check(go(side, from: "here", .down) == "other", "when nothing is lined up, the item that is there is still reached")

// --- Nearest item for recovering focus.
let nearestID = SpatialFocus.nearest(to: CGPoint(x: 650, y: 130), among: grid)
check(nearestID == "g1" || nearestID == "g2", "nearest: a lost focus lands on the tile where it was")



// --- NavRepeater: one step per push, repeats while held, sources independent, no flutter on a diagonal.
var rp = NavRepeater()
var t0: TimeInterval = 100
check(rp.updateDPad(x: 0, y: 1, now: t0) == [.up], "repeater: a D-pad push is one step at once")
check(rp.tick(now: t0 + 0.2).isEmpty, "repeater: no repeat before the first delay")
check(rp.tick(now: t0 + 0.41) == [.up], "repeater: the first repeat after the delay")
check(rp.tick(now: t0 + 0.50).isEmpty && rp.tick(now: t0 + 0.56) == [.up], "repeater: then every interval")
var early = 0, late = 0; var now = t0 + 0.56
for k in 0..<300 { now += 0.01; let n = rp.tick(now: now).count; if k < 60 { early += n } else if k >= 240 { late += n } }
check(late > early, "repeater: it speeds up while held (\(early) steps in the first 0.6 s, \(late) in the last 0.6 s)")
check(rp.updateDPad(x: 0, y: 0, now: now).isEmpty && !rp.isHolding && rp.tick(now: now + 1).isEmpty, "repeater: letting go stops it")
// the stick: hysteresis and sources independent
var st = NavRepeater()
check(st.updateStick(x: 0.5, y: 0, now: 0).isEmpty, "stick: a light push inside the dead zone does nothing")
check(st.updateStick(x: 0.7, y: 0, now: 0.01) == [.right], "stick: a firm push is one step")
check(st.updateStick(x: 0.45, y: 0.1, now: 0.02).isEmpty && st.isHolding, "stick: easing off a little keeps the direction (hysteresis)")
check(st.updateStick(x: 0.55, y: 0.6, now: 0.03).isEmpty && st.isHolding, "stick: a diagonal does not flip it (the other axis has to clearly win)")
check(st.updateStick(x: 0.2, y: 0.9, now: 0.04) == [.up], "stick: a clear turn changes direction at once")
check(st.updateStick(x: 0.1, y: 0.1, now: 0.05).isEmpty && !st.isHolding, "stick: letting back to centre stops it")
var both = NavRepeater()
_ = both.updateStick(x: 0.9, y: 0, now: 0)
check(both.updateDPad(x: -1, y: 0, now: 0.1) == [.left], "both: the D-pad takes over from a held stick")
check(both.updateDPad(x: 0, y: 0, now: 0.2) == [.right] && both.isHolding, "both: releasing the D-pad hands back to the still-held stick")
check(both.updateStick(x: 0, y: 0, now: 0.3).isEmpty && !both.isHolding, "both: and releasing that stops everything")


// --- PadAuto: keyboard-and-mouse for a game that never reads the controller, and back if it starts to.
var pa = PadAuto(); pa.begin(now: 0, reads: 100, preferKeys: false)
check(pa.update(now: 10, reads: 100, padConnected: true) == .none, "auto: the first seconds change nothing")
check(pa.update(now: 26, reads: 100, padConnected: false) == .none, "auto: no controller connected, nothing to switch")
check(pa.update(now: 26, reads: 100, padConnected: true) == .useKeys && pa.usingKeys, "auto: a game that has not read the controller in the grace period gets keyboard and mouse")
check(pa.update(now: 40, reads: 100, padConnected: true) == .none, "auto: and stays there while it still does not read")
check(pa.update(now: 50, reads: 7000, padConnected: true) == .useXInput && !pa.usingKeys, "auto: the moment the game reads the controller it gets the Xbox pad back")
check(pa.update(now: 90, reads: 9000, padConnected: true) == .none, "auto: and it is not switched again while it keeps reading")
check(pa.update(now: 400, reads: 9000, padConnected: true) == .none, "auto: nor if its reads pause for a long time (it has shown it supports the controller)")
var reading = PadAuto(); reading.begin(now: 0, reads: 0, preferKeys: false)
check(reading.update(now: 5, reads: 300, padConnected: true) == .none && reading.gameReads, "auto: a game that reads from the start is never switched")
check(reading.update(now: 120, reads: 300, padConnected: true) == .none, "auto: even if it pauses its reads later (it did read, so it supports the controller)")
var hinted = PadAuto(); hinted.begin(now: 0, reads: 50, preferKeys: true)
check(hinted.usingKeys && hinted.update(now: 1, reads: 50, padConnected: true) == .none, "auto: a game that did not read last time starts in keyboard and mouse")
check(hinted.update(now: 60, reads: 90, padConnected: true) == .useXInput, "auto: and reverts if it reads this time")

// --- FocusScope: a focused target that disappears hands focus to its nearest neighbour; one that comes straight back keeps it.
@MainActor func scopeTests() async {
    let scope = FocusScope(); scope.recoveryDelay = .milliseconds(20)
    for (id, f) in mixed { scope.register(id, frame: f, action: nil) }
    scope.focused = "e"
    scope.unregister("e"); scope.register("e", frame: mixed[5].frame, action: nil)       // a redraw: removed and added at once
    try? await Task.sleep(for: .milliseconds(80))
    check(fid(scope) == "e", "scope: a target that is removed and re-added keeps focus")
    scope.unregister("e")                                                                  // really gone
    try? await Task.sleep(for: .milliseconds(80))
    check(fid(scope) == "d" || fid(scope) == "f" || fid(scope) == "wide", "scope: a vanished target hands focus to a neighbour (\(fid(scope) ?? "nil"))")
    // the remembered column: c -> wide -> down lands on f
    let s2 = FocusScope()
    for (id, f) in mixed { s2.register(id, frame: f, action: nil) }
    s2.focused = "c"; s2.handle(.move(.down)); s2.handle(.move(.down))
    check(fid(s2) == "f", "scope: up/down through a wide row keeps the column (\(fid(s2) ?? "nil"))")
    s2.handle(.move(.up)); s2.handle(.move(.up))
    check(fid(s2) == "c", "scope: and back up to where it started")
    s2.handle(.move(.left)); s2.handle(.move(.down))
    check(fid(s2) == "wide" || fid(s2) == "b" || fid(s2) == "e" || fid(s2) == "a", "scope: a sideways move forgets the column")
    // select on a vanished focus finds somewhere to be instead of doing nothing
    let s3 = FocusScope(); s3.register("only", frame: r(0, 0, 100, 50), action: nil); s3.focused = "gone"; s3.handle(.select)
    check(fid(s3) == "only", "scope: a press with focus on something that is gone picks a target")
    // a screen with no targets ends with no focus
    let s4 = FocusScope(); s4.recoveryDelay = .milliseconds(10); s4.register("x", frame: r(0, 0, 10, 10), action: nil); s4.focused = "x"; s4.unregister("x")
    try? await Task.sleep(for: .milliseconds(60))
    check(fid(s4) == nil, "scope: nothing left, nothing focused")
}
await scopeTests()

// MARK: - The in-game menu chord

do {
    var c = PadChord()
    let mv = PadChordSetting.menuView
    check(!c.update(held: 0x0010, mask: mv, now: 0), "chord: one of two buttons is not the chord")
    check(!c.update(held: 0x0030, mask: mv, now: 1.0), "chord: both down, the clock starts")
    check(!c.update(held: 0x0030, mask: mv, now: 1.3), "chord: not yet held long enough")
    check(c.update(held: 0x0030, mask: mv, now: 1.55), "chord: fires after half a second")
    check(!c.update(held: 0x0030, mask: mv, now: 3.0), "chord: only once while held")
    check(c.isDown(held: 0x0030, mask: mv) && !c.isDown(held: 0x0010, mask: mv), "chord: isDown needs every button")
    _ = c.update(held: 0, mask: mv, now: 3.1)
    check(!c.update(held: 0x0030, mask: mv, now: 4.0) && c.update(held: 0x0030, mask: mv, now: 4.6), "chord: fires again after a release")
    check(!c.update(held: 0x00F0, mask: 0, now: 9), "chord: off never fires")
    check(PadChordSetting.mask(for: "") == PadChordSetting.menuView && PadChordSetting.mask(for: "L3R3") == PadChordSetting.l3r3
          && PadChordSetting.mask(for: "off") == 0 && PadChordSetting.mask(for: "home") == PadChordSetting.home, "chord: the options map to masks")
    check(PadChordSetting.name(mask: mv, kind: .dualSense) == "Options + Create" && PadChordSetting.name(mask: mv, kind: .xbox) == "Menu + View"
          && PadChordSetting.name(mask: mv, kind: .dualShock) == "Options + Share", "chord: named for the pad")
    var r = PadReleaseMask()
    r.latch(0x2000)                               // B was down when the menu closed
    check(r.apply(0x2000) == 0, "release mask: B stays hidden from the game while held")
    check(r.apply(0x2001) == 0x0001, "release mask: other buttons pass")
    check(r.apply(0) == 0 && r.apply(0x2000) == 0x2000, "release mask: let go once, B works again")
}

// MARK: - Button remapping (Xbox mode)

do {
    let a: UInt16 = 0x1000, b: UInt16 = 0x2000, x: UInt16 = 0x4000
    let swap = PadRemap(map: ["A": "B", "B": "A"])
    var r = swap.apply(buttons: a, lt: 0, rt: 0)
    check(r.buttons == b && r.lt == 0 && r.rt == 0, "remap: A and B swapped, A pressed -> B")
    r = swap.apply(buttons: b | x, lt: 0, rt: 0)
    check(r.buttons == a | x, "remap: B -> A, X untouched")
    r = swap.apply(buttons: a | b, lt: 0, rt: 0)
    check(r.buttons == a | b, "remap: both pressed stay both")
    check(PadRemap(map: [:]).apply(buttons: a | x, lt: 200, rt: 30) == (a | x, 200, 30), "remap: empty map changes nothing, triggers keep their value")
    check(PadRemap(map: ["A": "A"]).isEmpty && !swap.isEmpty, "remap: identity entries are an empty remap")
    check(PadRemap(map: ["A": "none"]).apply(buttons: a | x, lt: 0, rt: 0).buttons == x, "remap: none disables a button")
    r = PadRemap(map: ["A": "RT"]).apply(buttons: a, lt: 0, rt: 0)
    check(r.rt == 255 && r.buttons == 0, "remap: a button as a trigger is a full pull")
    r = PadRemap(map: ["LT": "A", "RT": "B"]).apply(buttons: 0, lt: 200, rt: 100)
    check(r.buttons == a | b && r.lt == 0 && r.rt == 0, "remap: triggers as buttons past the threshold")
    r = PadRemap(map: ["LT": "A"]).apply(buttons: 0, lt: 40, rt: 0)
    check(r.buttons == 0, "remap: a light trigger touch is not a button")
    r = PadRemap(map: ["LT": "RT", "RT": "LT"]).apply(buttons: 0, lt: 90, rt: 210)
    check(r.lt == 210 && r.rt == 90, "remap: swapped triggers keep their analog values")
    r = PadRemap(map: ["LB": "LT"]).apply(buttons: 0x0100, lt: 0, rt: 0)
    check(r.lt == 255, "remap: bumper as left trigger")
    r = PadRemap(map: ["A": "B", "X": "B"]).apply(buttons: a | x, lt: 0, rt: 0)
    check(r.buttons == b, "remap: two buttons onto one")
    check(PadRemap.targets.contains("none") && PadRemap.targets.count == 17, "remap: every button and nothing is a target")
}

// MARK: - Controller kinds

do {
    func kind(_ cat: String, _ vendor: String = "", ds5: Bool = false, ds4: Bool = false, xbox: Bool = false) -> ControllerKind {
        ControllerKind.classify(productCategory: cat, vendorName: vendor, dualSenseProfile: ds5, dualShockProfile: ds4, xboxProfile: xbox)
    }
    check(kind("DualSense", "DualSense Wireless Controller", ds5: true) == .dualSense, "kind: DualSense by profile")
    check(kind("HID", "DualSense Wireless Controller") == .dualSense, "kind: DualSense by name")
    check(kind("DualShock 4", "DUALSHOCK 4 Wireless Controller", ds4: true) == .dualShock, "kind: DualShock 4")
    check(kind("Xbox One", "Xbox Wireless Controller", xbox: true) == .xbox && kind("HID", "Xbox Series X Controller") == .xbox, "kind: Xbox")
    check(kind("HID", "Pro Controller") == .switchPro && kind("HID", "Joy-Con (L)") == .switchPro && kind("Switch Pro Controller") == .switchPro, "kind: Nintendo pads")
    check(kind("MFi", "8BitDo") == .generic, "kind: anything else is generic")
    check(ControllerKind.dualSense.glyph("A") == "\u{2715}" && ControllerKind.dualSense.glyph("LB") == "L1" && ControllerKind.dualSense.glyph("View") == "Create"
          && ControllerKind.dualShock.glyph("View") == "Share", "kind: PlayStation glyphs")
    check(ControllerKind.xbox.glyph("A") == "A" && ControllerKind.generic.glyph("LB") == "LB" && ControllerKind.none.glyph("View") == "View", "kind: Xbox names stay")
    check(ControllerKind.switchPro.glyph("A") == "B" && ControllerKind.switchPro.glyph("B") == "A" && ControllerKind.switchPro.glyph("RT") == "ZR", "kind: Nintendo letters by position")
    check(ControllerKind.dualSense.label("A") == "A (\u{2715})" && ControllerKind.xbox.label("A") == "A" && ControllerKind.dualSense.label("D\u{2191}") == "D\u{2191}", "kind: labels add the printed glyph only when it differs")
    check(ControllerKind.dualSense.menuChordName == "Options + Create" && ControllerKind.switchPro.menuChordName == "+ + \u{2212}", "kind: chord names")
}

print(failures == 0 ? "\nAll navigation checks passed." : "\n\(failures) check(s) FAILED.")
