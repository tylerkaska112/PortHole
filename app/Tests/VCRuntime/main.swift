// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

// Mac test for VCRuntime.swift. Needs Microsoft's installer, which is not in this repository:
//   VC_REDIST=/path/to/VC_redist.x64.exe app/Tests/VCRuntime/run.sh
// Without it only the refusal cases run.
var failures = 0
func check(_ name: String, _ ok: Bool) { print(ok ? "ok   \(name)" : "FAIL \(name)"); if !ok { failures += 1 } }

// Things that are not the installer are refused, never half-used.
do { _ = try VCRuntimeFiles.extract(installer: Data()); check("empty data is refused", false) }
catch { check("empty data is refused", (error as? VCRuntimeFiles.Failure) == .notTheExpectedInstaller) }
do { _ = try VCRuntimeFiles.extract(installer: Data(count: VCRuntimeFiles.installerBytes)); check("right size, wrong content is refused", false) }
catch { check("right size, wrong content is refused", (error as? VCRuntimeFiles.Failure) == .notTheExpectedInstaller) }
check("a cabinet header must be complete", Cabinet(data: Data("MSCF".utf8), at: 0) == nil)

if let path = ProcessInfo.processInfo.environment["VC_REDIST"], let installer = try? Data(contentsOf: URL(fileURLWithPath: path)) {
    let start = Date()
    do {
        let files = try VCRuntimeFiles.extract(installer: installer)
        check("all 12 DLLs come out and match their pinned hashes (\(String(format: "%.1f", Date().timeIntervalSince(start))) s)", files.count == 12)
        check("they are PE files", files.values.allSatisfy { $0.prefix(2) == Data("MZ".utf8) })
    } catch { check("extract the real installer: \(error.localizedDescription)", false) }

    var damaged = installer
    damaged[damaged.count / 2] ^= 0xff
    do { _ = try VCRuntimeFiles.extract(installer: damaged); check("one flipped byte in the installer is refused", false) }
    catch { check("one flipped byte in the installer is refused", (error as? VCRuntimeFiles.Failure) == .notTheExpectedInstaller) }
} else {
    print("skip  real installer (set VC_REDIST)")
}
print(failures == 0 ? "ALL GOOD" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
