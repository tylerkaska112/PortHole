# Porthole's Steam client: what it is and where it comes from

`app/Sources/Steam` signs in to Steam, lists the games an account owns, and downloads them into the Windows environment. It is not a Steam emulator and does
not touch DRM: Valve's own client (through Madeira Dock) still checks the licence when a game is started, and Steam itself refuses keys and files for games
the account does not own.

## Where the code comes from
- Written 2026-09-21 to 2026-09-23 (an AI assistant working for the project owner) for an earlier Madeira-based project, from Steam's **public** protocol:
  the Steam Web API (`IAuthenticationService`, `IContentServerDirectoryService`, `ISteamDirectory`), the connection-manager protocol (protobuf messages over a
  WebSocket, the framing and message numbers that open-source Steam clients such as SteamKit2 and DepotDownloader document), the content-server layout
  (manifests, depot keys, encrypted chunks) and the file formats (Valve text and binary KeyValues, zip / VZip-LZMA / VZstd chunks, RFC 8878 Zstandard).
  The protocol facts were checked against Steam's live servers with an anonymous log-on when it was written, and again on 2026-10-02 (the live tests below).
- That was **before** Madeira's own Steam client (`SwiftSteam`, derived from Jfishin's code) appeared in Madeira's repository (2026-09-30), and none of that
  code was used (the sessions that wrote this never refer to it). The old folder `app/Runtime/SwiftSteam` was removed when this code replaced it.
- Recovered on 2026-10-02 from the earlier project's session logs, then adapted: client-type sign-in so one sign-in serves the library, downloads and Dock;
  the owned-games list from the account's licence list; launch options and sizes; adaptive download speed; the app's own folders and progress type.
- The Zstandard decoder was written from RFC 8878 and is tested against the reference `zstd` tool; the LZMA decoder against `xz`. Third-party code: none.

## Tests
`app/Tests/Steam/run.sh` runs 69 checks against a stand-in for Steam's servers (files, resume, retries, ownership, failures, formats).
`STEAM_LIVE=1 app/Tests/Steam/run.sh` also installs Steam's free sample app (Spacewar, ~2 MB) from the real servers, anonymously, and builds the list of installable
games from Steam's public anonymous package (584 games when this was written).

## Not yet tested (needs a real account on a device)
Signing in (password + Steam Guard, QR), the log-on with the account's own refresh token, the licence list of a real account, and the hand-over to Dock.
