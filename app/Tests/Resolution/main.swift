import Foundation
// Run: app/Tests/Resolution/run.sh
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "ok   " : "FAIL ", what); if !ok { failures += 1 } }
let wide = 16.0 / 9.0

check(DisplayResolution.resolve(id: nil, screenAspect: wide) == DisplayResolution(width: 1280, height: 720), "no id gives 1280x720")
check(DisplayResolution.resolve(id: "1920x1080", screenAspect: wide).text == "1920 \u{00D7} 1080", "a fixed size is read as written")
check(DisplayResolution.resolve(id: "640x360", screenAspect: 4.0 / 3.0) == DisplayResolution(width: 640, height: 360), "a fixed size does not depend on the screen")
for id in DisplayResolution.allIDs { check(DisplayResolution.resolve(id: id, screenAspect: wide).width > 0, "\(id) resolves") }
check(DisplayResolution.resolve(id: "screen720", screenAspect: 4.0 / 3.0) == DisplayResolution(width: 960, height: 720), "screen shape on a 4:3 iPad is 960x720")
check(DisplayResolution.resolve(id: "screen720", screenAspect: 2160.0 / 1000.0) == DisplayResolution(width: 1556, height: 720), "screen shape on a long phone follows its shape, width even")
check(DisplayResolution.resolve(id: "screen1080", screenAspect: wide) == DisplayResolution(width: 1920, height: 1080), "screen shape 1080 on 16:9 is 1920x1080")
check(DisplayResolution.resolve(id: "screen720", screenAspect: 0) == DisplayResolution(width: 1280, height: 720), "a bad screen shape falls back to 16:9")
check(DisplayResolution.resolve(id: "screen720", screenAspect: 9.0) == DisplayResolution(width: 1728, height: 720), "an absurd screen shape is limited to 2.4:1")
check(DisplayResolution.resolve(id: "banana", screenAspect: wide) == .fallback, "an unknown id gives the default")
check(DisplayResolution.resolve(id: "100x100", screenAspect: wide) == .fallback, "too small gives the default")
check(DisplayResolution.resolve(id: "9000x9000", screenAspect: wide) == .fallback, "too large gives the default")
check(DisplayResolution.resolve(id: "screen5", screenAspect: wide) == .fallback, "a screen-shape height out of range gives the default")
check(DisplayResolution.title(id: "1280x720", screenAspect: wide) == "1280 \u{00D7} 720 (default)", "the default is named")
check(DisplayResolution.title(id: "screen720", screenAspect: 4.0 / 3.0) == "Screen shape, 960 \u{00D7} 720", "a screen-shape title shows the real size")
check(!DisplayResolution.allIDs.contains("2560x1440"), "2560x1440 is not offered any more")
check(DisplayResolution.resolve(id: "2560x1440", screenAspect: wide) == .fallback, "a saved 2560x1440 falls back to the default size")
check(DisplayResolution.resolve(id: "1366x768", screenAspect: wide) == .fallback, "any size the app does not offer falls back to the default")
check(DisplayResolution.offered("2560x1440") == nil && DisplayResolution.offered("1600x900") == "1600x900" && DisplayResolution.offered(nil) == nil, "offered() keeps only listed ids")
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
