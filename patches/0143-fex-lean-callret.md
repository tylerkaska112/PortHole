# 0143 FEX (ARM64EC module): lean call/return code (ON by default since 0.50.341; `MADEIRA_FEX_LEAN=0` switches it off)

`FEX/FEXCore/.../JIT/BranchOps.cpp, JIT.cpp, JITClass.h, Dispatcher/Dispatcher.cpp, include/FEXCore/Debug/InternalThreadState.h, Source/Windows/Common/CallRetStack.h` (submodule FEX; `git -C vendor/Madeira/FEX apply`). Build: see "Building the translator" below. Output `libarm64ecfex.dll` is shipped as `xtajit64.dll`.

Evidence (The Forest, profile of 2026-10-14 22:07/22:19): 55% of the hot places inside the audio library's functions were `call`/`ret` instructions; the dumped ARM code of those places shows what one guest CALL costs: ~13 ARM instructions (return address constant 3, guest push 1, call-ret stack reload 1, bounds guard 5, push 3), one guest RET about the same again (reload, guard 6, pop, writeback, L1 lookup 7, ret), and every return point repeats a 5-instruction block header (header store 2, suspend-doorbell check 3).

Changes (all behind `MADEIRA_FEX_LEAN=1`, read once; with it unset the emitted code is the old one):
* **Guard in 2 instructions** (`Arm64JITCore::EmitCallRetGuard`, three sites in BranchOps.cpp, the dispatcher's sentinel push): the call-ret stack lives in a window [base+2MB, base+6MB) and was put back at base+4MB when it left it, checked with ldr+add+sub+lsr+cbz. With the base on an 8MB boundary the window is bits 22:21 of sp = 01 or 10, i.e. `eor tmp, sp, sp, lsr #1; tbnz tmp, #21` (taken when inside); the reset is `and sp, sp, #~0x7fffff; orr sp, sp, #0x400000` with no load. Model-checked against the old arithmetic for every 16-byte sp in the stack's 8MB block: identical. 6 fewer instructions per CALL+RET pair.
* **Aligned base** (always, harmless without the flag): `CallRetStack::InitializeThread` reserves 8MB more address space and moves `CallRetStackBase` up to an 8MB boundary inside the reservation; the reservation start is kept in `InternalThreadState::CallRetStackReservation` (new field before BaseFrameState; used by GetInfoThread / DestroyThread).
* **No doorbell check at a call-return point**: `EmitEntryPoint(..., SkipSuspendCheck)`: the thread-suspend check (`ldr w; cbz; brk #0xcafe`) is not emitted at the entry point a CALL falls through into. The call's target (a function entry) and every backward branch still have one. 2 fewer executed instructions per call return.

Building the translator (reproducible; the old script lacked these options):
```
R=vendor/Madeira; export PATH="$R/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin:$PATH"
cmake -S $R/FEX -B <dir> -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=$R/FEX/Data/CMake/toolchain_mingw.cmake -DMINGW_TRIPLE=arm64ec-w64-mingw32 \
  -DFEX_IOS_HOST_BUILD=ON -DCMAKE_C_FLAGS=-DFEX_IOS_HOST -DCMAKE_CXX_FLAGS=-DFEX_IOS_HOST -DCMAKE_ASM_FLAGS=-DFEX_IOS_HOST -DENABLE_LTO=OFF -DENABLE_ASSERTIONS=OFF \
  -DENABLE_FEX_ALLOCATOR=ON -DENABLE_JEMALLOC_GLIBC_ALLOC=ON -DENABLE_OFFLINE_RUNTIME=ON -DBUILD_FEXCONFIG=ON -DENABLE_CLANG_THUNKS=ON -DBUILD_TESTING=OFF -DBUILD_THUNKS=OFF \
  -DTUNE_ARCH=generic -DTUNE_CPU=none -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_DISABLE_FIND_PACKAGE_fmt=ON -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew
cmake --build <dir> --target arm64ecfex -j 6        # ~4 min; LTO ON fails to link (EC-mangled libc++ symbols)
```
Result 5,423,104 bytes (the shipped Oct-7 DLL: 5,439,488; same sections, .text 24 KB smaller: some option or revision difference of the original build is not known). The shipped file is kept as `ec-out/xtajit64.shipped-oct7.orig.dll`.
Results (2026-10-14, 0.50.339-340, iPhone 15 Pro Max, hot): The Forest with `MADEIRA_FEX_LEAN=1`: the log's `[lean] ... ON`, the dumped ARM code shows the 2-instruction guard (`eor x10, x17, x17, lsr #1; tbnz w10, #0x15`) and the call-return label reduced to `adr; str`; the FMOD mixer thread's busy share 65 % -> 46 % (profile, same 30 s, same scene type), the main game thread unchanged at 92 % busy, frame rate unchanged (28.4 vs 28.3 mean) because the main thread's code is Mono/Unity code, not tiny call-heavy functions. Factorio with the flag: 59.3 fps mean (min 50), no crash. 0.50.341 turns it on by default.
