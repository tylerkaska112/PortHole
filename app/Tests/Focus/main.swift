import CoreGraphics
// Run: app/Tests/Focus/run.sh
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "ok   " : "FAIL ", what); if !ok { failures += 1 } }

// A 3x2 grid of tiles (200x100, 20 apart), a wide hero above, and a tab bar on top.
func tile(_ col: Int, _ row: Int) -> CGRect { CGRect(x: 20 + CGFloat(col) * 220, y: 300 + CGFloat(row) * 120, width: 200, height: 100) }
let items: [(id: String, frame: CGRect)] = [
    ("tabHome", CGRect(x: 20, y: 0, width: 100, height: 40)), ("tabSteam", CGRect(x: 130, y: 0, width: 100, height: 40)), ("tabSettings", CGRect(x: 240, y: 0, width: 100, height: 40)),
    ("hero", CGRect(x: 20, y: 60, width: 640, height: 220)),
    ("g00", tile(0, 0)), ("g10", tile(1, 0)), ("g20", tile(2, 0)), ("g01", tile(0, 1)), ("g11", tile(1, 1)),
]
func go(_ from: String, _ d: NavDirection) -> String? { SpatialFocus.next(from: items.first { $0.id == from }!.frame, among: items, direction: d, excluding: from) }

check(go("g00", .right) == "g10" && go("g10", .right) == "g20", "right walks along a row")
check(go("g20", .right) == nil, "right at the end of a row goes nowhere")
check(go("g10", .left) == "g00", "left walks back")
check(go("g10", .down) == "g11", "down goes to the tile below")
check(go("g20", .down) == "g11" || go("g20", .down) == nil, "down from a tile with nothing below it lands on the nearest below, or nowhere")
check(go("g11", .up) == "g10", "up goes to the tile above")
check(go("g00", .up) == "hero", "up from the first row goes to the hero")
check(go("hero", .down) == "g00" || go("hero", .down) == "g10", "down from the hero lands on the first row")
check(["tabHome", "tabSteam", "tabSettings"].contains(go("hero", .up) ?? ""), "up from the hero reaches the tab bar (the tab nearest its centre)")
check(go("tabHome", .right) == "tabSteam" && go("tabSteam", .left) == "tabHome", "tabs are reached sideways")
check(go("tabSettings", .down) == "hero", "down from a tab goes to the content")
check(go("tabHome", .up) == nil && go("tabHome", .left) == nil, "nothing above or left of the first tab")
check(SpatialFocus.first(among: items) == "tabHome", "with no focus yet the top-left item gets it")
check(SpatialFocus.next(from: tile(0, 0), among: [(id: "only", frame: tile(0, 0))], direction: .right, excluding: "only") == nil, "a single item has nowhere to go")
// An item lined up beats a nearer one that is off to the side (not by much: three times as near would win, as the rule says).
let lined = [(id: "far", frame: CGRect(x: 600, y: 300, width: 100, height: 100)), (id: "near", frame: CGRect(x: 400, y: 700, width: 100, height: 100))]
check(SpatialFocus.next(from: CGRect(x: 0, y: 300, width: 100, height: 100), among: lined, direction: .right) == "far", "an item in line beats a nearer one far off the axis")
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
