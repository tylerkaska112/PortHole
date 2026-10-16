# In-app JIT via an app extension (as implemented in Iridium)

Source read: `Iridium-20260924.tar.gz` > `iridium/apps/ios/BuiltinJIT/` (Host/, Helper/, Shared/, Vendor/, prepare.py). Nothing copied into this project yet.

## Why an extension
A process that attaches a debugger to itself deadlocks. So a SEPARATE process (the extension) attaches a debugserver to the host's PID, enables JIT, and detaches.

## Flow
1. Host app is signed with `get-task-allow` (checked with SecTaskCopyValueForEntitlement) and embeds `Helper.appex`.
2. Helper Info.plist: `NSExtensionPointIdentifier = com.apple.ar.viewer`, `NSExtensionActivationRule = FALSEPREDICATE`, `XPCService ServiceType = Application`,
   principal class `JITRequestHandler`. (The AR-viewer point is just a vehicle that lets the host start the extension as its own process.)
3. Host starts it with PRIVATE NSExtension API: `+extensionWithIdentifier:excludingDisabledExtensions:error:`, `-beginExtensionRequestWithInputItems:error:`,
   `-pidForRequestIdentifier:`. It passes an anonymous `NSXPCListenerEndpoint` in the input item's userInfo.
4. Helper's own `NSExtensionMain` swizzles `NSXPCDecoder _validateAllowedClass:forKey:allowingInvocations:` to also allow NSXPCListenerEndpoint (only that class), then calls Apple's.
5. Helper connects back over XPC. Host accepts only if `connection.processIdentifier == helperPID`. Host calls `worker.enable(pid, pairing)`; helper checks `pid == connection.processIdentifier`.
6. Helper calls `StikJIT.enableJIT(targetPID:pairingFile:ddiPaths:script:...)` (StikJIT.xcframework 1.5.0, MPL-2.0, wraps jkcoxson/idevice MIT):
   probe tunnel `10.7.0.1:49152` -> check/download/mount DDI -> detect TXM -> attach debugserver to host PID -> run JS script (`madeira-jit.js`) -> detach.
7. Script prints a marker; host verifies `jit_check_debugged()` and then proceeds. 180 s overall timeout; helper kept alive after a failure (do not kill it while attached).

## Requirements (NOT self-contained)
- **LocalDevVPN** (separate app) connected, and Wi-Fi or Airplane Mode on. Our app cannot provide the tunnel itself without a Network Extension entitlement.
- A **pairing file** (plist: identifier, 32-byte public_key/private_key) imported once, from a computer.
- DDI mounted (once per boot; downloaded by StikJIT).
- Host AND extension need valid signing; the extension needs its own bundle id/App ID. Iridium dropped it for free Apple IDs (App ID cap).
- Host `get-task-allow`. A distribution/enterprise profile normally lacks it. CHECK your own developer profile before relying on this.
- Iridium's guard: iOS 18+. Private API: never App Store. Debugger already attached (Xcode) blocks it.

## Licences
StikJIT framework MPL-2.0; idevice MIT; `universal.js`/`legacy.js` from StikDebug AGPL-3.0; `madeira-jit.js` GPL-3.0 (Madeira). Retain notices (Iridium keeps them in `StikJITNotices/`).

## Pinned binary
`https://github.com/StikDebug/StikJIT/releases/download/1.5.0/StikJIT.xcframework.zip` sha256 444b8d439df8455c34afbb51e279fd225265279195475f9b3fdbcf3a71a27e85 (from Iridium's prepare.py; not downloaded or verified by us yet).

## Signing facts (user, 2026-09-30)
- A development profile for this needs get-task-allow, increased-memory-limit, extended-virtual-addressing, packet-tunnel-provider, vpn.api. App id is exact (not wildcard); profile is device-locked.
- User reports the iPad has its own cert and that the same app+extension layout (Iridium) has signed and run before, so appex signing works on their setup. Re-verify with our own build.
