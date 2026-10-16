# How the tunnel, in-app JIT and self-updating work

Written for people who want to build the same thing into another app (for example Madeira). Everything here describes what Porthole actually does; the file
names point at the code. Nothing in this document is secret: the only things that are per-user are the pairing file and the signing certificate/profile,
and both stay on the device.

## The idea in one paragraph

An iPhone or iPad can run a debugger against one of its own apps, and a debugger is allowed to do what a JIT needs (map executable memory). The catch is that
the debugger normally runs on a computer and talks to the device over USB or Wi-Fi. This app does the same thing **from inside the device**: it starts a
tiny local VPN whose only job is to make the device's own address answer on the device itself, uses a pairing file so the device trusts "the computer" (which is
the app), runs a small helper process that attaches a debugserver to the app, and then lets Madeira's JIT script answer the app's requests. The same
connection (tunnel + pairing file) is also used to **install an updated copy of the app on the device**, after the app has re-signed the new build
itself with the user's own certificate. No computer and no server is needed for either.

```
 App (get-task-allow)                          Helper extension (own process)
 ───────────────────                           ──────────────────────────────
 1. start tunnel ──► Packet tunnel extension
 2. start helper (private NSExtension API) ──► JITRequestHandler
 3. XPC: enable(pid, pairingFile) ───────────► StikJIT.enableJIT(...)
                                                  │  connect 10.7.0.1:49152 (through the tunnel)
                                                  │  mount developer disk image if needed
                                                  │  attach debugserver to the app's pid
                                                  └► run madeira-jit.js (answers BRK #0xf00d requests)
 4. jit_check_debugged() turns true ◄── debugger is attached; app carries on starting the game
 5. a few seconds after the game starts: tunnel off
```

## The pieces

### 1. The app's signing requirements
* `get-task-allow` entitlement (so it can be debugged). The app checks it at runtime (`F4HasDebugEntitlement`, `JITExtensionLauncher.m`).
* The app and **both extensions** must be signed with provisioning profiles that carry the right entitlements:
  `get-task-allow`, `com.apple.developer.networking.networkextension = [packet-tunnel-provider]` (app and tunnel extension), plus whatever the runtime needs
  (`increased-memory-limit`, `extended-virtual-addressing`). A free Apple ID profile cannot carry the Network Extension entitlement, so this needs a paid
  account or a signing service that provides it.
* Each extension needs its own App ID (`<app id>.tunnel`, `<app id>.jithelper`). The project builds unsigned (`CODE_SIGNING_ALLOWED=NO`) and gets signed later.

### 2. The loopback tunnel (`app/Tunnel/PacketTunnelProvider.swift`, `app/Sources/Core/TunnelManager.swift`)
* A normal `NEPacketTunnelProvider`. It claims the subnet `10.7.0.0/24` and routes **only that subnet** to itself. Nothing else on the device is routed through it.
* The JIT library (idevice/StikJIT) is hard-wired to reach the device's debug services at **`10.7.0.1`** (the address LocalDevVPN uses).
  The tunnel makes that address come back to the phone itself: it reads each packet, **swaps source and destination address**, and writes it back.
  The phone's network stack then sees a packet "from 10.7.0.1" addressed to itself, hands it to the local service, and the reply takes the same path.
  IP/TCP/UDP checksums are symmetric in the two addresses, so no checksum needs recomputing. IPv4 only.
* Why a VPN at all: iOS gives an app no other way to make its own device reachable at that address. It is not a real VPN: no traffic leaves the device.
* Use from the app (`TunnelManager`):
  * `NETunnelProviderManager` creates the configuration the first time (`saveToPreferences`). iOS shows its "Add VPN configurations" prompt once.
  * `connect()` starts it and waits for `.connected`. It retries, and after two failures **deletes its own VPN configuration and creates a new one**
    (an app update can leave iOS holding a stale configuration or a record of the old extension; reinstalling the app used to be the only cure).
  * "Connecting" and straight back to "disconnected" within seconds means iOS refused to run the extension. After an app update that is cured by
    **restarting the device**; the app says so instead of waiting for a timeout.
  * iOS allows **one VPN at a time**. Turning ours on turns another VPN off and vice versa; a disabled configuration is re-enabled and saved again.
  * It is only on while needed: it is turned off a few seconds after the game process starts, and at app start any tunnel left on is stopped
    (`stopLeftoverTunnel`).
  * If another VPN (LocalDevVPN) already provides `10.7.0.1`, the app uses that instead (`deviceReachable()` probes the address).

### 3. The pairing file (`app/Sources/Pairing/*`)
* iOS only lets a "paired computer" attach a debugger or use the installer. A pairing file (an XML plist: `public_key`, `private_key`, `identifier`, `alt_irk`)
  is the long-term identity that proves "I am the paired host". Normally a computer makes it over USB.
* **From iOS 27 the device can pair with something on the same Wi-Fi from its own Settings** (Privacy & Security > Developer Mode > "Pair with <name>").
  The app implements the *host* side (`RemotePairingHost`): it advertises Bonjour `_remotepairing-pairable-host._tcp`, runs the remote-pairing handshake and an
  SRP-3072 pair-setup, shows a six-digit code for the person to type into the device, and ends up with the pairing file. The app stays alive while the person
  goes to Settings (silent audio keep-alive and a `BGContinuedProcessingTask`) and notifies with the code.
* The protocol was documented by the idevice project (Jackson Coxson) and shown working by StikPair (StephenDev0 and the StikDebug team). Porthole's code is a
  separate Swift implementation; see `PairingCredits` and `CREDITS.md`.
* Older iOS versions: make the file on a computer with a pairing tool (iloader, Jitterbug…) and import it. The file is stored in the app's Documents
  (`StikJIT/pairingFile.plist`), complete file protection, excluded from backup.
* Needs the Local Network permission.

### 4. The JIT helper extension (`app/Helper/*`, `app/Sources/Core/JITExtensionLauncher.*`, `app/Sources/Core/BuiltinJIT.swift`)
* **Why a separate process:** a process cannot debug itself (it deadlocks). So an app extension, running as its own process, attaches to the app.
* The extension's point identifier is `com.apple.ar.viewer` with `NSExtensionActivationRule = FALSEPREDICATE` and `XPCService ServiceType = Application`.
  It is only a *vehicle*: it lets the host start the extension on demand as its own process; nothing else is ever offered it.
* The host starts it with **private NSExtension API** (`+extensionWithIdentifier:excludingDisabledExtensions:error:`,
  `-beginExtensionRequestWithInputItems:error:`, `-pidForRequestIdentifier:`). This is why the app can never be on the App Store.
* The host passes an **anonymous `NSXPCListenerEndpoint`** in the input item. `NSExtension` decodes input items with a class allow-list that does not include that
  class, so the helper's own `NSExtensionMain` (`ExtensionMain.m`) widens the allow-list by exactly that one class (and refuses to start if the private selector changes).
* The helper connects back over XPC. The host accepts exactly one connection and only from the process id it just started; the helper only accepts an
  `enable` for its own host's pid. Request: `worker.enable(pid, pairing)`.
* The helper calls `StikJIT.enableJIT(targetPID:pairingFile:ddiPaths:script:…)` (the StikJIT xcframework, which wraps idevice). That:
  1. checks the tunnel (connects to `10.7.0.1:49152`),
  2. checks/downloads/mounts Apple's **developer disk image** if it is not mounted (once per boot),
  3. attaches a debugserver to the host's pid,
  4. runs **Madeira's `madeira-jit.js`** against that debugserver.
* The host knows JIT is ready when `jit_check_debugged()` (the `CS_DEBUGGED` code-signing flag, read with `csops(getpid(), CS_OPS_STATUS)`) turns true (polled every 0.25 s; 180 s overall timeout).
  Then it continues starting the game.
* Lesson learned: if the helper fails while the debugger is attached, do **not** kill the helper or drop the tunnel; that wedges the app. Only tear down on a clean finish.

### 5. What the JIT script does (`vendor/Madeira/app/Madeira/madeira-jit.js`)
* Attaches (`vAttach`), tells debugserver to ignore Mach exceptions the app handles itself (`QSetIgnoredExceptions`) and to pass signals through without stopping
  (`QPassSignals`, except SIGTRAP), because servicing every signal made the debug session slow enough for iOS to kill the helper's host.
* Then it loops: continue, and on each stop that is a **`BRK #0xf00d`** it reads `x16` as a command: 0 = detach, 1 = prepare a JIT memory region
  (`_M` allocate / `prepare_memory_region`), 3 = map at a fixed address, and so on; it writes the result into `x0`, advances `pc` by 4 and continues.
  Any other stop is handed back to the process as a signal; if it cannot be delivered the script detaches so the process dies visibly.
* The runtime side is `app/Runtime/JITAllocator.c` (`jit_check_debugged`, and the BRK-based allocation calls). Constraint found the hard way: the JIT pool
  must be contiguous and sit below the guest address window (see `docs/ENGINE.md`).

## Self-updating

### What the updater is
The app contains the Launcher's tested core (`Packages/LauncherCore`): a signer, a credential vault and an install pipeline. `UpdateService` registers *this app*
as one of the things it can update.

### The flow
1. **Find a build.** The app asks a server (the "Hub") for `updates/<id>/latest.json` and `versions.json`. They are static files; the server can be any static host.
   `latest.json` names a build number and a file. A newer build number than the running one means an update is available.
2. **Download** the unsigned IPA (cached by SHA-256; progress shown).
3. **Sign it on the device** (`IPASigner`):
   * The user's `.p12` certificate and `.mobileprovision` profile(s) are stored in the Keychain (`CredentialVault`). Nothing leaves the device.
   * Bundles are signed deepest first (loose dylibs, frameworks, extensions/Watch apps, then the app) because each seal covers the finished files inside it.
   * Each bundle gets the best matching profile for its own bundle id (`ProfileMatcher`); its entitlements come from the profile; the Mach-O code directory,
     page hashes and the CMS signature are written by the app itself.
   * The new build **must have the installed bundle id and be signed by the same team** as the installed copy, otherwise iOS silently keeps the old version.
     (The app reads its own running bundle id, since a signing service may have changed it, and signs with that.)
4. **Install on this device** (`OnDeviceInstaller`), using the same tunnel and pairing file as JIT:
   * Open a remote-pairing tunnel to `10.7.0.1:49152` with the pairing file (`tunnel_create_rppairing`).
   * Copy the signed IPA into the device's `PublicStaging` folder over **AFC** (the file-transfer service), in 1 MB chunks.
   * Ask **installation_proxy** to install it (`Install`/`Upgrade` with `{"PackageType": "Developer"}`), exactly what a computer does over USB. Progress comes
     back as percentages. Several ways of asking are tried in turn (a plain install got no answer on a real device); each is abandoned after 25 s without a reply.
   * Important detail: **the app's own tunnel runs inside the app being replaced.** When iOS starts replacing the app it stops the app's extensions, which would cut
     the install connection. Another VPN providing 10.7.0.1 does not have that problem, so if one is on it is used instead.
5. **No fallback to a server (changed in 0.50.218).** If the device cannot install the signed build (no pairing file, the private link is not up, iOS refuses),
   the signed IPA is kept as a file and offered to the share sheet ("Save or share the signed file") so it can be installed with a tool of the person's own.
   It is never uploaded anywhere. (Earlier builds could `POST` it to the Hub and open an `itms-services://` link; that code is gone.)

### Cellular data (`app/Sources/Core/CellularGuard.swift`)
The loopback does not work while cellular data is the network in use (Madeira documents the same limit for LocalDevVPN: "works on Wi-Fi, or with no network at all, but
not while cellular data is in use"; why is not known). Neither JIT nor the install needs the internet, so `CellularGuard` switches Cellular Data off for the job:

1. Before the tunnel starts, if the network path is cellular only (`NWPathMonitor`: cellular in use, no Wi-Fi, no cable), it asks once ("Switch cellular data off?").
   The first time it offers the two shortcuts instead and stops.
2. The tunnel comes up **first**, while cellular data still works (a VPN that is not up yet may not connect with no network; one that is up keeps working).
3. Then the `Porthole Cellular Off` shortcut runs. An app cannot switch Cellular Data itself; the only way is a Shortcut with the action `Set Cellular Data`
   (`is.workflow.actions.cellulardata.set`, `OnValue` 0 = off, no parameters = on). The app opens `shortcuts://x-callback-url/run-shortcut?name=...` and the Shortcuts app
   returns to `porthole://cellular?result=ok|cancel|error` (`ShortcutRouter`). The app waits for that, then for the path to stop being cellular.
4. JIT: after the JIT pool is mapped and the debugger has detached (`SessionController`, right after `StikJITHelper.detachDebugger()`), `CellularGuard.restoreBlocking()` runs
   `Porthole Cellular On` before Wine starts. Update: the install runs with cellular off; after a successful install the app restarts and switches it back on at launch; after a
   failed install it does so at once.
5. "Switched off by Porthole" is kept in `f4.cellularPaused` across launches, so a crash or an update cannot leave it off: it is retried when the app opens, when a game ends, and
   the Home screen shows a notice with a Turn on button if it still could not.

The two shortcut files are bundled (`app/Shortcuts/*.shortcut`, one action each). iOS only accepts files signed by Apple: they were made from a plain workflow plist and signed with
`shortcuts sign --mode anyone` on a Mac (the action id and parameters were read from Madeira's signed `Madeira JIT.shortcut`). **Their signing certificate expires on 10 Nov 2027:**
sign them again before then (same plist, same command) and replace the files. They are added through the share sheet (choose Shortcuts, Add Shortcut); Settings > JIT and tunnel >
Cellular data has the button, a test (it switches cellular data off and back on once), and the off switch for the whole feature.

### Not verified / honest limits
* The on-device install path depends on private-ish services (AFC, installation_proxy over remote pairing); behaviour can change between iOS versions.
* A tunnel/profile problem looks like "the VPN did not connect" with little detail; `TunnelDiagnostics` collects iOS's disconnect reason and a signing report.
* After updating the app, the first tunnel start can be refused until the device is restarted.

## What another app needs to copy, in order

1. Entitlements and profiles: `get-task-allow`; `packet-tunnel-provider` on app and tunnel extension; per-extension App IDs.
2. The tunnel extension (about 50 lines) and a manager that saves/starts/retries/resets its configuration.
3. The pairing file: import from a computer, or the iOS 27 on-device pairing host.
4. The helper extension, the private NSExtension launcher, the XPC protocols (`app/Sources/Shared`) and the StikJIT xcframework (MPL-2.0; wraps idevice, MIT).
5. `madeira-jit.js` plus the runtime's BRK protocol (`JITAllocator.c`).
6. For updates: an IPA signer that runs on the device, the certificate/profile vault, and the AFC + installation_proxy install path above.

## Credits and licences
* idevice (Jackson Coxson, MIT): the device protocols and the C interface the app calls.
* StikJIT / StikDebug (StikDebug team): the JIT enabling library and the original script.
* StikPair (StephenDev0 and the StikDebug team): showed on-device pairing working.
* LocalDevVPN: the `10.7.0.1` convention.
* Madeira (125hz and contributors): the JIT script and the runtime.
* Iridium: the app-extension layout for in-app JIT (see `docs/JIT-in-app.md`).

Where to read the code: `app/Tunnel`, `app/Helper`, `app/Sources/Pairing`, `app/Sources/Core/{TunnelManager,BuiltinJIT,JITExtensionLauncher,OnDeviceInstaller,UpdateService}`,
`app/Runtime/JITAllocator.c`, `Packages/LauncherCore`.
