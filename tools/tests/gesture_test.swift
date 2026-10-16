import Foundation
import CoreGraphics

// Scripted-touch tests for TouchGestureEngine (compile together with it:  swiftc -o t TouchGestureEngine.swift gesture_test.swift).
final class Rec: PointerSink {
    var log: [String] = []
    func pointerMove(_ p: CGPoint) { log.append("move(\(Int(p.x)),\(Int(p.y)))") }
    func pointerPress(_ b: MouseButton, at p: CGPoint) { log.append("press \(b)(\(Int(p.x)),\(Int(p.y)))") }
    func pointerRelease(_ b: MouseButton, at p: CGPoint) { log.append("release \(b)(\(Int(p.x)),\(Int(p.y)))") }
    func pointerClick(_ b: MouseButton, at p: CGPoint) { log.append("click \(b)(\(Int(p.x)),\(Int(p.y)))") }
    func pointerWheel(_ d: Int32, at p: CGPoint) { log.append("wheel \(d)") }
}
var failures = 0
func check(_ name: String, _ got: [String], _ want: [String]) {
    if got == want { print("PASS  \(name)") } else { failures += 1; print("FAIL  \(name)\n   got:  \(got)\n   want: \(want)") }
}
func run(_ name: String, primary: MouseButton = .left, _ script: (TouchGestureEngine, Rec) -> Void, expect: [String]) {
    let e = TouchGestureEngine(), r = Rec(); e.sink = r; e.primary = primary
    script(e, r); check(name, r.log, expect)
}

run("tap = move, then one left click at lift", { e, _ in
    e.began(1, at: CGPoint(x: 100, y: 100), time: 0); e.ended(1, at: CGPoint(x: 101, y: 100), time: 0.1)
}, expect: ["move(100,100)", "click left(101,100)"])

run("drag = left held from the START point, moves, released at lift", { e, _ in
    e.began(1, at: CGPoint(x: 100, y: 100), time: 0); e.moved(1, to: CGPoint(x: 140, y: 100), time: 0.05)
    e.moved(1, to: CGPoint(x: 200, y: 110), time: 0.1); e.ended(1, at: CGPoint(x: 200, y: 110), time: 0.15)
}, expect: ["move(100,100)", "press left(100,100)", "move(140,100)", "move(200,110)", "release left(200,110)"])

run("small wobble stays a tap", { e, _ in
    e.began(1, at: CGPoint(x: 100, y: 100), time: 0); e.moved(1, to: CGPoint(x: 105, y: 103), time: 0.05); e.ended(1, at: CGPoint(x: 105, y: 103), time: 0.1)
}, expect: ["move(100,100)", "click left(105,103)"])

run("press-and-hold = RIGHT held at the start point; no left click", { e, _ in
    e.began(1, at: CGPoint(x: 50, y: 60), time: 0); e.tick(time: 0.1); e.tick(time: 0.31); e.ended(1, at: CGPoint(x: 50, y: 60), time: 0.9)
}, expect: ["move(50,60)", "press right(50,60)", "release right(50,60)"])

run("hold then drag keeps the right button down while moving", { e, _ in
    e.began(1, at: CGPoint(x: 50, y: 60), time: 0); e.tick(time: 0.35)
    e.moved(1, to: CGPoint(x: 90, y: 60), time: 0.5); e.ended(1, at: CGPoint(x: 90, y: 60), time: 0.6)
}, expect: ["move(50,60)", "press right(50,60)", "move(90,60)", "release right(90,60)"])

run("two-finger tap = right click at the midpoint, no left click", { e, _ in
    e.began(1, at: CGPoint(x: 100, y: 100), time: 0); e.began(2, at: CGPoint(x: 200, y: 100), time: 0.02)
    e.ended(1, at: CGPoint(x: 100, y: 100), time: 0.12); e.ended(2, at: CGPoint(x: 200, y: 100), time: 0.13)
}, expect: ["move(100,100)", "click right(150,100)"])

run("pinch out = wheel up (zoom in)", { e, _ in
    e.began(1, at: CGPoint(x: 100, y: 100), time: 0); e.began(2, at: CGPoint(x: 200, y: 100), time: 0.02)
    e.moved(2, to: CGPoint(x: 240, y: 100), time: 0.1); e.ended(1, at: CGPoint(x: 100, y: 100), time: 0.3); e.ended(2, at: CGPoint(x: 240, y: 100), time: 0.31)
}, expect: ["move(100,100)", "wheel 360"])

run("pinch in = wheel down; a pinch is not also a tap", { e, _ in
    e.began(1, at: CGPoint(x: 100, y: 100), time: 0); e.began(2, at: CGPoint(x: 300, y: 100), time: 0.02)
    e.moved(2, to: CGPoint(x: 250, y: 100), time: 0.1); e.ended(1, at: CGPoint(x: 100, y: 100), time: 0.2); e.ended(2, at: CGPoint(x: 250, y: 100), time: 0.21)
}, expect: ["move(100,100)", "wheel -240"])

run("a second finger during a drag changes nothing; only the drag's lift releases", { e, _ in
    e.began(1, at: CGPoint(x: 100, y: 100), time: 0); e.moved(1, to: CGPoint(x: 150, y: 100), time: 0.05)
    e.began(2, at: CGPoint(x: 300, y: 300), time: 0.1); e.ended(2, at: CGPoint(x: 300, y: 300), time: 0.2); e.ended(1, at: CGPoint(x: 150, y: 100), time: 0.3)
}, expect: ["move(100,100)", "press left(100,100)", "move(150,100)", "release left(150,100)"])

run("an extra finger lifting AFTER the held finger does not strand anything", { e, _ in
    e.began(1, at: CGPoint(x: 100, y: 100), time: 0); e.moved(1, to: CGPoint(x: 150, y: 100), time: 0.05)
    e.began(2, at: CGPoint(x: 300, y: 300), time: 0.1); e.ended(1, at: CGPoint(x: 150, y: 100), time: 0.2); e.ended(2, at: CGPoint(x: 300, y: 300), time: 0.3)
    e.began(3, at: CGPoint(x: 5, y: 5), time: 1); e.ended(3, at: CGPoint(x: 5, y: 5), time: 1.1)
}, expect: ["move(100,100)", "press left(100,100)", "move(150,100)", "release left(150,100)", "move(5,5)", "click left(5,5)"])

run("RIGHT MODE: tap = right click", primary: .right, { e, _ in
    e.began(1, at: CGPoint(x: 10, y: 10), time: 0); e.ended(1, at: CGPoint(x: 10, y: 10), time: 0.1)
}, expect: ["move(10,10)", "click right(10,10)"])

run("RIGHT MODE: drag = right held; two-finger tap = LEFT click", primary: .right, { e, _ in
    e.began(1, at: CGPoint(x: 10, y: 10), time: 0); e.moved(1, to: CGPoint(x: 80, y: 10), time: 0.05); e.ended(1, at: CGPoint(x: 80, y: 10), time: 0.1)
    e.began(2, at: CGPoint(x: 100, y: 100), time: 1); e.began(3, at: CGPoint(x: 120, y: 100), time: 1.02)
    e.ended(2, at: CGPoint(x: 100, y: 100), time: 1.1); e.ended(3, at: CGPoint(x: 120, y: 100), time: 1.11)
}, expect: ["move(10,10)", "press right(10,10)", "move(80,10)", "release right(80,10)", "move(100,100)", "click left(110,100)"])

run("cancel while held releases the button, sends no click", { e, _ in
    e.began(1, at: CGPoint(x: 50, y: 60), time: 0); e.tick(time: 0.4); e.cancelled(1)
}, expect: ["move(50,60)", "press right(50,60)", "release right(50,60)"])

run("the engine is reusable after every gesture (tap, tap)", { e, _ in
    e.began(1, at: CGPoint(x: 1, y: 1), time: 0); e.ended(1, at: CGPoint(x: 1, y: 1), time: 0.1)
    e.began(2, at: CGPoint(x: 9, y: 9), time: 1); e.ended(2, at: CGPoint(x: 9, y: 9), time: 1.1)
}, expect: ["move(1,1)", "click left(1,1)", "move(9,9)", "click left(9,9)"])

print(failures == 0 ? "\nall gesture tests passed" : "\n\(failures) FAILED"); exit(failures == 0 ? 0 : 1)
