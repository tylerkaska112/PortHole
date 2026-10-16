# 0120 Madeira pull request 235 (external SSD Steam library) and 207 (Epic Games)

## 235: the glue
`0120-madeira-pr-235-external-library.patch` is the pull request's diff for the files Porthole vendors from `vendor/Madeira/app/Madeira`, applied to the snapshot tree:
`MadeiraDock.swift` (`DockGame.storageID`, `clientInstallPath`, `games(library:root:)`, `validate(libraryRoot:)`), `DockInstallers.swift` (E: paths, `externalRoot`), `SteamInstall.swift`
(`SteamLibraryFolders.register`, a throwing `SteamInstallFiles.delete`), `SteamKeyValues.swift`, `WineProcessBridge.m` (E: resolution, working folder), and the new `SteamStorage.swift`
and `SteamStorageNative.h` (added to `FILES` in `tools/vendor_glue.sh`). Porthole's own side: `app/Sources/Core/ExternalLibrary.swift` (the catalog, the scoped lease, the session mapping),
`SteamStore.swift` (a download goes to the library chosen for it, an install on the SSD is answered from the catalog), `SessionController.swift` (the drive is mapped before a Steam game
starts, the game is checked under that scope, shared apps and the language record go to the game's own `steamapps`), Settings > Steam and JIT > Game storage. See `docs/EXTERNAL_STORAGE.md`.

## 207: Epic Games
New files only: `app/Sources/Epic/EpicAuth.swift`, `EpicAPI.swift`, `EpicManifest.swift`, `EpicChunk.swift`, `EpicInstaller.swift`, `EpicSignInView.swift` from the pull request (a port of derrod's
Legendary), with `EpicInstaller` adapted (Porthole's game list instead of Madeira's library, `EpicBackground` instead of `SteamDownloadBackground`); the screens (`app/Sources/UI/EpicPage.swift`)
are Porthole's. `Game` gained `epicAppName`, `epicLaunchCommand`, `epicArtworkURL`, `epicHeroURL`. A launch fetches an exchange code after JIT is on and appends Legendary's
`-AUTH_LOGIN=unused -AUTH_PASSWORD=<code> ...` to the arguments for that run only (`SessionController.launchResolved`); the saved game and the log never hold it (`madeira_redact.h` hides
`-AUTH_PASSWORD`). See `docs/EPIC.md`.

Neither is verified on a device in Porthole. Both pull requests' authors tested on an iPad/iPhone.
