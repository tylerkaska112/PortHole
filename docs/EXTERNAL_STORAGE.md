# External SSD game library

Porthole supports one registered external library next to the device's own. It is the design of **willfaust/Madeira pull request 235** (David Brookes; GPL-3.0-or-later with Madeira's
converter exception), taken as `app/Runtime/SteamStorage.swift`, `SteamStorageNative.h` and its glue changes (`MadeiraDock.swift`, `DockInstallers.swift`, `SteamInstall.swift`,
`SteamKeyValues.swift`, `WineProcessBridge.m`, patch 0120), with Porthole's own model and screens (`app/Sources/Core/ExternalLibrary.swift`, Settings > Stores and JIT > Steam > Game storage).

## What the person does
Settings > Stores and JIT > Steam > Game storage > **Choose an SSD library folder** (a dedicated folder on a locally attached drive). **New downloads go to the SSD** sends every Steam game
downloaded from then on there; a game already installed, or half downloaded, stays where it is. Check the SSD connection / Select the library folder again are there for a drive that was unplugged.

## Storage and identity
Game files, `appmanifest` records, `downloading` journals and depot caches live in `<folder>/steamapps`. The Wine prefix, the registry, Steam's client files and the normal Windows user
folders stay on the device. An internal catalog (`Application Support/steam-storage.json`) holds a library UUID, the folder's security-scoped bookmark and each game's library and relative
path; a `.madeira-library-id` marker file in the folder tells it from another drive mounted at the same path. A missing marker is never recreated on reconnect.

## Windows paths
A session maps the folder twice, both to the same directory: `dosdevices/e:` (E:, used by direct starts, installers and working folders; the native bridge resolves E: only with the
registered identity and the marker) and `drive_c/MadeiraExternalLibrary` (Valve's client rejects E: as unmounted, so it is registered as a Steam library at `C:\MadeiraExternalLibrary` in
`libraryfolders.vdf`; Dock's expected install path uses it). A library entry of a game on the SSD points at `C:\MadeiraExternalLibrary\steamapps\common\...`.

## Limits
One external library; no moving an install between libraries; no network shares or cloud providers; unplugging the drive during a game can end the session and lose unsaved progress.
Not verified on a device in Porthole (the pull request's author tested Brotato and Borderlands GOTY on an iPad).
