import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FAIL: \(what)") } }

let keys = ["Software\\Wow6432Node\\Ubisoft\\Launcher", "Software\\Ubisoft\\Launcher"]
let values = [(name: "InstallDir", data: "C:\\Program Files (x86)\\Ubisoft\\Ubisoft Game Launcher\\")]
let base = "WINE REGISTRY Version 2\n\n[Software\\\\Wow6432Node\\\\Valve] 1\n\"x\"=dword:00000001\n\n"

// missing keys are created in both views
var (text, added) = DockRegistryRepair.add(keys: keys, values: values, in: base, now: 5)
check(added == 2, "adds 2 values, got \(added)")
check(text.contains("[Software\\\\Wow6432Node\\\\Ubisoft\\\\Launcher] 5\n\"InstallDir\"=\"C:\\\\Program Files (x86)\\\\Ubisoft\\\\Ubisoft Game Launcher\\\\\""), "32-bit view written")
check(text.contains("[Software\\\\Ubisoft\\\\Launcher] 5\n"), "64-bit view written")
check(text.contains("\"x\"=dword:00000001"), "existing content kept")

// idempotent
let again = DockRegistryRepair.add(keys: keys, values: values, in: text, now: 9)
check(again.added == 0 && again.text == text, "second run changes nothing")

// an existing value (even different) is left alone; a key lacking the value gets it
let other = base + "[Software\\\\Wow6432Node\\\\Ubisoft\\\\Launcher] 3\n\"InstallDir\"=\"D:\\\\Mine\\\\\"\n\n[Software\\\\Ubisoft\\\\Launcher] 3\n\"Other\"=\"y\"\n"
let r = DockRegistryRepair.add(keys: keys, values: values, in: other, now: 9)
check(r.added == 1, "adds only to the key lacking it, got \(r.added)")
check(r.text.contains("\"InstallDir\"=\"D:\\\\Mine\\\\\""), "existing value untouched")
check(r.text.contains("\"Other\"=\"y\"\n\"InstallDir\""), "added inside the key that lacked it")

// run(): only with the marker file, writes a backup once
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("repair-\(UUID().uuidString)")
let drive = tmp.appendingPathComponent("drive_c"), prefix = tmp
try! FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
try! Data(base.utf8).write(to: prefix.appendingPathComponent("system.reg"))
check(DockRegistryRepair.run(drive: drive, prefix: prefix).isEmpty, "no marker, no repair")
let dir = drive.appendingPathComponent("Program Files (x86)/Ubisoft/Ubisoft Game Launcher")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
FileManager.default.createFile(atPath: dir.appendingPathComponent("UbisoftGameLauncher.exe").path, contents: Data([1]))
var logged: [String] = []
check(DockRegistryRepair.run(drive: drive, prefix: prefix, log: { logged.append($0) }) == ["Ubisoft Connect"], "repairs with the marker")
check(logged.count == 1, "one log line")
check(FileManager.default.fileExists(atPath: prefix.appendingPathComponent("system.reg.madeira-bak").path), "backup kept")
check(DockRegistryRepair.run(drive: drive, prefix: prefix).isEmpty, "second run repairs nothing")
let onDisk = String(decoding: try! Data(contentsOf: prefix.appendingPathComponent("system.reg")), as: UTF8.self)
check(onDisk.contains("\"InstallDir\"="), "written to system.reg")
try? FileManager.default.removeItem(at: tmp)

// force: a value that holds something else is replaced, only when asked
let wrong = base + "[Software\\\\Valve\\\\Steam] 3\n\"SteamPath\"=\"C:\\\\NIS B1~AG\"\n\"Language\"=\"english\"\n\n"
let fv = [(name: "SteamPath", data: "C:/Program Files (x86)/Steam")]
let f1 = DockRegistryRepair.add(keys: ["Software\\Valve\\Steam"], values: fv, force: true, in: wrong, now: 9)
check(f1.added == 1 && f1.text.contains("\"SteamPath\"=\"C:/Program Files (x86)/Steam\"") && !f1.text.contains("NIS B1"), "force replaces a wrong value")
check(f1.text.contains("\"Language\"=\"english\""), "force leaves other values")
let f2 = DockRegistryRepair.add(keys: ["Software\\Valve\\Steam"], values: fv, force: true, in: f1.text, now: 9)
check(f2.added == 0 && f2.text == f1.text, "force is idempotent")
let f3 = DockRegistryRepair.add(keys: ["Software\\Valve\\Steam"], values: fv, force: false, in: wrong, now: 9)
check(f3.added == 0 && f3.text == wrong, "without force a wrong value stays")

print(failures == 0 ? "All registry repair checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
