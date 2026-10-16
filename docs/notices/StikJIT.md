# StikJIT 1.5.0, idevice and StikDebug

**What is in Porthole.** The JIT helper extension contains `StikJIT.framework`, the library from the StikDebug team that attaches a debugger to Porthole and switches
JIT on ("Built-in" JIT). It is the unmodified release binary plus two small build-time changes described below. Porthole does **not** contain the StikDebug app.
Porthole's own script that the helper runs is `madeira-jit.js` (from Madeira, GPL-3.0-or-later). `universal.js` and `legacy.js` are two scripts that ship inside
the StikJIT release; Porthole does not run them.

**Licence of StikJIT: Mozilla Public License 2.0** (the repository's LICENSE file, in full in "MPL-2.0-StikJIT"). Its source code is public:

- Source of the exact release: https://github.com/StikDebug/StikJIT/tree/640fac91de403fdb85a3778aa0bbb7f30737b74c (tag `1.5.0`)
- Release archive Porthole uses: https://github.com/StikDebug/StikJIT/releases/tag/1.5.0, SHA-256 `444b8d439df8455c34afbb51e279fd225265279195475f9b3fdbcf3a71a27e85`

Under the MPL you may get that source code from the address above, and any file of StikJIT stays under the MPL. Porthole's own files are not MPL "Larger Work" parts.

**What Porthole changed** (`tools/prepare_stikjit.py`, in this repository): the framework had no `Info.plist`, which iOS signing needs, so one was added; and in the
`.swiftinterface` text files the module-name prefix `StikJIT.` was removed so they compile with current Xcode. The compiled library, `universal.js` and `legacy.js` are
untouched.

**What is inside StikJIT.** Statically linked: **idevice** by Jackson Coxson (jkcoxson), MIT (https://github.com/jkcoxson/idevice), and about 130 Rust libraries, all under permissive
licences (MIT, Apache-2.0, BSD-3-Clause, ISC, Unicode-3.0, Zlib, Unlicense). Their names, versions and licence texts are in "StikJIT-rust-libraries".
`aws-lc-rs` is built on AWS-LC, whose licence terms also include OpenSSL and BoringSSL-derived parts (https://github.com/aws/aws-lc/blob/main/LICENSE).

**StikDebug.** The StikDebug app (https://github.com/StikDebug/StikDebug, AGPL-3.0) is a separate program; Porthole only opens it through its URL scheme when you choose it as the JIT method.
The same team's StikPair (MIT) and Iridium's way of enabling JIT from inside an app were the starting points of Porthole's own code for pairing and for the on-device tunnel; those parts
are written by Porthole's authors and are listed in CREDITS.md.

No warranty: see each licence.
