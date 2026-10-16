import UIKit

// Same shape as GameHUDView: a root with an overriding hitTest, a top bar added FIRST, then a full-screen "controls" container added AFTER (so it is above the bar).
class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { let v = super.hitTest(point, with: event); return v === self ? nil : v }
}
class Root: UIView {
    // identical to GameHUDView.hitTest: only controls count, everything else falls through
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let v = super.hitTest(point, with: event) else { return nil }
        return v is UIControl ? v : nil
    }
}
func build(passthrough: Bool) -> (root: Root, esc: UIButton, panelKey: UIButton) {
    let root = Root(frame: CGRect(x: 0, y: 0, width: 844, height: 390))
    let esc = UIButton(type: .system); esc.frame = CGRect(x: 20, y: 10, width: 60, height: 36)
    let bar = UIView(frame: root.bounds); bar.addSubview(esc); root.addSubview(bar)                      // top bar, added first
    let controls: UIView = passthrough ? PassthroughView(frame: root.bounds) : UIView(frame: root.bounds) // full-screen container, added after: on top
    let key = UIButton(type: .system); key.frame = CGRect(x: 700, y: 330, width: 44, height: 38); controls.addSubview(key)
    root.addSubview(controls)
    return (root, esc, key)
}
for (name, pass) in [("OLD (plain full-screen container)", false), ("NEW (pass-through container)   ", true)] {
    let h = build(passthrough: pass)
    let onEsc = h.root.hitTest(CGPoint(x: 50, y: 28), with: nil)
    let onKey = h.root.hitTest(CGPoint(x: 720, y: 345), with: nil)
    let onGame = h.root.hitTest(CGPoint(x: 400, y: 200), with: nil)
    print("\(name): tap Esc -> \(onEsc === h.esc ? "Esc button" : onEsc == nil ? "NOTHING (touch lost)" : "other")   | tap key panel -> \(onKey === h.panelKey ? "key button" : "other")   | tap empty game area -> \(onGame == nil ? "falls through to game" : "swallowed")")
}
