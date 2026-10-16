# 0099 Dock: register wintrust.dll before a launcher runs

`app/Runtime/DockInstallers.swift` (`DockInstallScripts.batch`; applied by `tools/vendor_glue.sh` after 0085). With the service step on, the batch runs `C:\windows\system32\regsvr32.exe /s wintrust.dll` and writes `wintrust-registered <errorlevel>` to the result file.

Why (RDR2, log of 0.50.173 and earlier): the launcher window drew, the Social Club prerequisites installed (exit 0) and `socialclub.dll` loaded, but the launcher showed "The Rockstar Games SDK failed to load due to an incomplete installation (code 1002)".
The log has `fixme:cryptasn:CryptDecodeObjectEx Unsupported decoder for lpszStructType 1.3.6.1.4.1.311.2.1.4` (SPC_INDIRECT_DATA_CONTENT, the Authenticode digest structure) in the launcher's process, before the dialog.
Wine's wintrust.dll provides those decoders only after its DllRegisterServer has put them in the registry (HKLM\Software\Microsoft\Cryptography\OID\...) together with its trust providers; a normal prefix gets that from wine.inf at creation,
this one never did, so a program that checks the Authenticode signature of its own libraries cannot, and says its installation is incomplete.

Not verified on a device: it is a guess that this is what the SDK's check needs. Look for `wintrust-registered 0` in the dock-installers result and for the fixme to be gone from the next log; if the dialog stays, the next suspects are the trust providers
(`WinVerifyTrust` itself) and the certificate chain of Rockstar's signature (their root in the Wine root store).

0.50.177: in the log of 0.50.176 (a clean "Run them all again" start) the three installers ran and exited 0, but `regsvr32.exe` never started: the ARM64EC farm (`app/Madeira/arm64ec-windows`) has no regsvr32.exe (only the i386 farm does, which would register in the 32-bit registry view), and the
`CryptDecodeObjectEx Unsupported decoder ... 1.3.6.1.4.1.311.2.1.4` line was still there. Wine's own ARM64EC build (`wine/build-arm64ec/programs/regsvr32/arm64ec-windows/regsvr32.exe`, 1 MB) is copied to `$F4_BUILD_ROOT/ec-out/regsvr32.exe`, and `tools/stage_runtime.sh` now copies
`ec-out/*.exe` as well as `*.dll` into the farm.
