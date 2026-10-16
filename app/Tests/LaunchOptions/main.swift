import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FAIL: \(what)") } }

let base = "\"UserLocalConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"apps\"\n\t\t\t\t{\n\t\t\t\t\t\"427520\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"LastPlayed\"\t\t\"1\"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n"
// new app block
var t = DockLaunchOptions.setting("-insecure -nosound", appID: 730, in: base)!
check(t.contains("\"730\"") && t.contains("\"LaunchOptions\"\t\t\"-insecure -nosound\""), "adds an app block")
check(t.contains("\"LastPlayed\"\t\t\"1\""), "keeps other apps")
// idempotent
check(DockLaunchOptions.setting("-insecure -nosound", appID: 730, in: t) == nil, "second run changes nothing")
// change value
t = DockLaunchOptions.setting("-insecure", appID: 730, in: t)!
check(t.contains("\"LaunchOptions\"\t\t\"-insecure\"") && !t.contains("-nosound"), "replaces the value")
// existing app block without the key
let t2 = DockLaunchOptions.setting("+exec x", appID: 427520, in: base)!
check(t2.contains("\"LaunchOptions\"\t\t\"+exec x\"") && t2.contains("\"LastPlayed\""), "adds the key inside an existing app block")
// remove
let t3 = DockLaunchOptions.setting("", appID: 730, in: t)!
check(!t3.contains("LaunchOptions"), "empty removes the line")
check(DockLaunchOptions.setting("", appID: 999, in: base) == nil, "empty on an app without the key changes nothing")
// escaping
check(DockLaunchOptions.setting("+name \"a\\b\"", appID: 730, in: base)!.contains("\"+name \\\"a\\\\b\\\"\""), "escapes quotes and backslashes")
// CRLF kept
let crlf = base.replacingOccurrences(of: "\n", with: "\r\n")
let c = DockLaunchOptions.setting("-x", appID: 730, in: crlf)!
check(c.contains("\r\n") && !c.contains("\n\n") && c.hasSuffix("\r\n"), "CRLF file stays CRLF")
// no apps block
check(DockLaunchOptions.setting("-x", appID: 730, in: "\"UserLocalConfigStore\"\n{\n}\n") == nil, "no apps block: nothing")
// a launch options line in another app does not confuse it
let other = base.replacingOccurrences(of: "\"LastPlayed\"\t\t\"1\"", with: "\"LaunchOptions\"\t\t\"-keep\"")
let o = DockLaunchOptions.setting("-insecure", appID: 730, in: other)!
check(o.contains("\"-keep\"") && o.contains("\"-insecure\""), "other app's options untouched")
print(failures == 0 ? "All launch option checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
