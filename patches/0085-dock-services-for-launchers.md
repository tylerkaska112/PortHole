# 0085 the Dock starts Windows' service manager at every start for launchers that need it

`app/Runtime/DockInstallers.swift` (vendored; applied by tools/vendor_glue.sh). The Dock only wrote its service step (`dockhost.exe --start-services`, which starts services.exe and rpcss) when a
one-time install was pending. Once Rockstar's launcher was installed, RDR2's start (PlayRDR2.exe -> Launcher.exe) ran `RockstarService.exe install` and `start` with no service manager:
each exit code 1, no window ever appeared (log 2026-10-08 05:37). Now a start whose install scripts include Rockstar-Games-Launcher.exe (done or pending) gets the service step with
no program to run; `MADEIRA_DOCK_SERVICES=1` does the same for any Dock game. The same session switch as for installers applies (madsync off for that session).
Unverified on a device; whether `RockstarService.exe start` then succeeds is the next thing to read in the log (`services-step=start` on the `[dock-installers] ... scripts=` line).
