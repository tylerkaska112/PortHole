# 0101 Dock: register shell32, windowscodecs, urlmon, wintrust, cryptnet once (COM classes a prefix needs)

`app/Runtime/DockInstallers.swift` (`DockInstallScripts.batch`, replaces the single wintrust line of 0099; applied by `tools/vendor_glue.sh` after 0100). With the service step on, the batch runs, once (marker file `C:\madeira-com-registered.txt`):
`regsvr32.exe /s shell32.dll windowscodecs.dll urlmon.dll wintrust.dll cryptnet.dll` and writes `com-registered <errorlevel>` to the result file.

Why (RDR2, logs of 0.50.176/177, user report 2026-10-09: no `Social Club` folder under `Program Files\Rockstar Games`, only `Launcher`): Social-Club-Setup.exe (with `/silent`, from the Dock batch, and with `/silent /forceinstall`, from the launcher) ends with exit code 0 and installs nothing.
The log of the Dock run shows why: `err:ole:create_server class {56fdf344-fd6d-11d0-958a-006097c9a090} not registered` (CLSID_TaskbarList, registered by shell32.dll's DllRegisterServer) right before `exit_process raw_status=0x0`.
A normal Wine prefix registers those DLLs through wine.inf's RegisterDllsSection when it is created; this prefix never did. The launcher then finds no SDK (`socialclub.dll` of the Social Club folder) and reports "incomplete installation (code 1002)" and offers the installer again.
The five DLLs are the ones wine.inf registers that exist in the ARM64EC farm and are not media filters. A DLL that cannot register fails alone; regsvr32 goes on to the next.

After this build: tap "Run them all again" on the game's page (so Social Club's setup runs once more with the COM classes in place), start the game, and look for `com-registered 0`, a `Social Club` folder and no `not registered` line.
Not verified on a device.
