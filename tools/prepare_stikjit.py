#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Porthole authors. See LICENSE.
"""Fetch StikJIT 1.5.0 (StikDebug/StikJIT, MPL-2.0) into app/Vendor, digest-checked, and make it usable from Xcode 27.

Two fixes are needed (same ones any consumer of this release needs):
  * the published framework has no Info.plist, and iOS signing requires one;
  * under Xcode 27 the textual interface refers to its own module by name (`StikJIT.Foo`), which now clashes with the public enum `StikJIT`; strip that qualification.
The binary is untouched. Licences: StikJIT MPL-2.0; it bundles idevice (MIT) and StikDebug's universal.js/legacy.js (AGPL-3.0) -- keep notices (docs/notices/StikJIT.md).
"""
import hashlib, io, plistlib, sys, urllib.request, zipfile
from pathlib import Path

URL = "https://github.com/StikDebug/StikJIT/releases/download/1.5.0/StikJIT.xcframework.zip"
SHA256 = "444b8d439df8455c34afbb51e279fd225265279195475f9b3fdbcf3a71a27e85"
ROOT = Path(__file__).resolve().parent.parent / "app" / "Vendor"

data = open(sys.argv[1], "rb").read() if len(sys.argv) > 1 else urllib.request.urlopen(URL, timeout=120).read()
if hashlib.sha256(data).hexdigest() != SHA256:
    sys.exit("digest mismatch; nothing extracted")
ROOT.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(io.BytesIO(data)) as z:
    for e in z.infolist():
        if not (ROOT / e.filename).resolve().is_relative_to(ROOT.resolve()):
            sys.exit("unsafe path in archive")
    z.extractall(ROOT)
fw = ROOT / "StikJIT.xcframework" / "ios-arm64" / "StikJIT.framework"
for iface in (ROOT / "StikJIT.xcframework").rglob("*.swiftinterface"):
    iface.write_text(iface.read_text().replace("StikJIT.", ""))
(fw / "Info.plist").write_bytes(plistlib.dumps({
    "CFBundleIdentifier": "site.portholehq.vendor.StikJIT", "CFBundleName": "StikJIT", "CFBundleExecutable": "StikJIT",
    "CFBundlePackageType": "FMWK", "CFBundleShortVersionString": "1.5.0", "CFBundleVersion": "1.5.0",
    "MinimumOSVersion": "17.4", "CFBundleSupportedPlatforms": ["iPhoneOS"]}))
print("StikJIT 1.5.0 verified and prepared at", fw)
