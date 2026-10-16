# Publishing checklist: licences and other obligations

Working notes, **not legal advice**. Madeira's own `docs/LICENSING.md` says the same about itself and asks for a review by an open-source licensing lawyer
before any public release; that applies to this project too. Written 2026-10-02 from what the app actually ships.

## 1. Decisions that block publishing
1. **This project's licence: DONE (2026-10-02), GPL-3.0-or-later.** `LICENSE` (the GPL-3 text), `LICENSE-EXCEPTION.md` (our own converter exception, the same idea as Madeira's, for the
   Apple Metal Shader Converter; it can be deleted if you would rather not give it), `README.md`, and an SPDX + "Copyright (C) 2026 The Porthole authors" header on our own
   Swift/Python sources. The copyright holder name is deliberately the neutral "The Porthole authors"; put a legal name in if you prefer (headers, `LICENSE-EXCEPTION.md`).
   Files from other projects keep their own licences and are NOT marked ours: `app/Runtime` (Madeira glue), `patches/`, `SteamBackground.swift` is marked "portions adapted from Madeira".
   Still open: the in-app Licences screen and bundling `LICENSE` in the app (section "Notices inside the app" below).
2. **StikJIT: RESOLVED (2026-10-02).** The framework and its repository are MPL-2.0 (checked against the LICENSE file at tag 1.5.0, commit 640fac91). Earlier notes called `universal.js`/`legacy.js` AGPL-3.0;
   that is not supported by the StikJIT repository (they sit in its MPL-licensed `Resources` and carry no separate header), though the StikDebug *app* is AGPL-3.0 and is not included. Done: MPL text and source link
   in `docs/notices/StikJIT.md`, a list of the ~130 Rust libraries inside the binary with their licence texts (`StikJIT-rust-libraries.txt`), all shown in the app under Licences.
   Open: a lawyer should confirm the `aws-lc-rs` (AWS-LC, OpenSSL-derived parts) wording, and `cargo about` on idevice's own lockfile would confirm the library list is complete (ours is read from the binary).
3. **Steam code: RESOLVED (2026-10-02).** Madeira's Steam client (`SwiftSteam`, derived from Jfishin's code, with only a chat message as permission) has been removed from this project.
   Porthole's Steam sign-in, owned-games list and downloads are `app/Sources/Steam`, written for this project from Steam's public protocol; `docs/STEAM_CLIENT.md` records where it came
   from (written 2026-09-21..23, before SwiftSteam existed in Madeira's repo, with no use of Jfishin's code). `tools/export_public.sh` still refuses to export if `app/Runtime/SwiftSteam` ever
   comes back. Madeira Dock (125hz's own work) stays. What is still open here: Valve's terms for an unofficial client (item 4), and a clean-machine test of the sign-in.
   Credits to complete before publishing: the name of Iridium's creator (removed from `CREDITS.md` for now).
4. **Name.** An earlier working name used a game publisher's trademark; the app is now **Porthole** everywhere (display name, project, bundle id `site.portholehq.app`, file names). A trademark search for "Porthole" (2026-10-02, by the maintainer) found only unrelated apparel and restaurant marks. Same care for "Steam", "Epic", "GOG" in the UI: say "compatible with", never imply endorsement.

## 2. What the published app and repository must contain
- **Source for what we ship (GPL).** Our code is in `app/`. The Madeira runtime is NOT in our repo (`vendor/` is ignored), so the repo must pin the exact upstream commit(s)
  (submodule or a documented hash), include our patches (`patches/`, incl. 0009: the win32u display/message changes and the `wow64win` atom fix) and the build recipes we used for
  the files we rebuilt ourselves: `libwin32u_unix.a`, `wow64win.dll`, `gdiplus.dll`, the extra DLLs in `ec-out` (rstrtmgr, cabinet, ...). Every binary we modified needs its source reachable.
- **LGPL relink ability** (Wine, GnuTLS, FFmpeg are statically linked): provide what a recipient needs to rebuild and re-sign the app with a modified library (build instructions or object files).
  Madeira marks this "UNVERIFIED until a clean-machine rebuild is tested"; we need the same test.
- **Notices inside the app.** Already bundled (from Madeira): `legal/` (LICENSE, LICENSES, THIRD-PARTY-NOTICES), `licenses/`, and the Apple converter agreement + NOTICE in `d3d12/`.
  Still to add: our own LICENSE and `CREDITS.md`, the StikJIT / idevice / StikDebug notices (Iridium-style `StikJITNotices/`), the GPL source offer (link to the repository and commit), and a
  Licenses / Credits screen in the app.
- **Apple Metal Shader Converter** (`libmetalirconverter.dylib`, proprietary): may be redistributed only for shader conversion, only for use on Apple devices, with the agreement text
  alongside. Keep `d3d12/METAL-SHADER-CONVERTER-AGREEMENT.txt` and `NOTICE.txt` in the IPA; never offer it as a service or for non-Apple devices.

## 3. Things in the IPA that must not be redistributed as they are now
- **Microsoft's Visual C++ runtime DLLs: DONE in 0.28.0 (code side).** They are no longer in any IPA: `tools/package_app.sh` deletes `x86_64-vcruntime/*.dll` from the package
  (unless `F4_BUNDLE_VCRUNTIME=1`, for a private test build), and the app downloads Microsoft's own `VC_redist.x64.exe` (fixed content-addressed URL, 25,635,768 bytes, SHA-256 pinned),
  unpacks the 12 x64 DLLs itself (`app/Sources/Core/VCRuntime.swift`: Microsoft cabinet + MSZIP reader), re-checks each against its pinned SHA-256 and stores them in Application Support/Porthole.
  The setup guide has a step for it, Settings > Advanced and a Library notice offer it. `patches/0011` makes the Windows side prefer the downloaded folder.
  Left for the legal review: unpacking the installer skips its licence click-through (Madeira's documented method does too), and the installer URL is Microsoft's, so a new redistributable needs new pins.
  Test: `VC_REDIST=/path/to/VC_redist.x64.exe app/Tests/VCRuntime/run.sh`.
- Games, launchers and Windows installers (Factorio, Steam, Epic, GOG) are never bundled. Keep it that way, including in release IPAs and the repo (`.gitignore` already blocks `factorio*/`, `*.exe`).

## 4. Third-party services and terms
- **Steam.** `app/Sources/Steam` talks to Steam with an unofficial client implementation, and the Dock downloads and runs Valve's own client files (fetched from Valve at run time with pinned hashes,
  not redistributed). Read the Steam Subscriber Agreement and the Steamworks/Web API terms for what is allowed; state clearly in the README that the app is unofficial and
  does not bypass licence checks (the Dock design already verifies ownership).
- **Artwork** is loaded from Valve's CDN at run time, not stored in the repo; no Valve logos.
- **Apple.** The app uses a private NSExtension API for the in-app JIT helper, so it can never be on the App Store; it is distributed for sideloading only. The VPN (Network Extension),
  increased-memory and debugging entitlements need provisioning that belongs to each user.

## 5. Clean-up before the repository goes public
- **Personal data (code side done in 0.26.1).** No server address, app id, user name, path or e-mail is in the source or in a public-config build: identity comes from `app/Config/Local.xcconfig` (ignored by git); `tools/scrub_paths.py` rewrites the builder's user name inside compiled paths (DLL asserts, debug maps, shader bitcode) and `--strict` proves it (a build with no Local.xcconfig passes). `tools/export_public.sh` makes a one-commit copy without `logs/`, `STATUS.md`, `baseline/` or the history (which has the author's e-mail and machine name) and refuses to finish if `tools/public_banned.txt` matches anything. Still manual: publish from that export, never from this repo; a public build has no compatibility server until one is chosen.
  device names, account names and tokens. Confirm no `.p12`, `.mobileprovision`, pairing file, Steam token or `hub.token` is in git history (history scan, not just the working tree).
- **LauncherCore** is now vendored in `Packages/LauncherCore` (generic: no personal servers or app ids; per-build identity comes from `app/Config/*.xcconfig`). It still needs the project licence applied.
- **Tests and vectors.** The pairing self-test uses a public test vector from idevice's tests (auth tag): attribute it (done in `CREDITS.md`).

## 6. Credits (keep current)
See `CREDITS.md`. Still missing: Iridium's creator's name, and anything else you took inspiration from. StikPair's licence is MIT non-commercial: we use none of its code, but keep the credit
and do not copy its files into this repository.

## Steam Cloud (added 0.50.10)
Porthole reads the signed-in person's own Steam Cloud file list and downloads their files for a game before it is started through Steam (`app/Sources/Steam/SteamCloud.swift`). It uses Steam's service messages from Porthole's own authenticated connection, is download-only, and was written from the message definitions, not from another client's code. Uploads are not implemented. Valve's terms for unofficial clients (see item 4 above) apply to this as to the rest of the Steam client.
