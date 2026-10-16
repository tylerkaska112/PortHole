# 0130 ntdll names Microsoft C++ throws (diagnostic, log only)

`wine/dlls/ntdll/signal_arm64ec.c`, next to ml811's decoder. ml811 decodes LLVM/libc++abi throws (`0x20474343`) and the game's own report codes, but not the exceptions that MSVC and clang-cl programs raise (`0xe06d7363`).
A game that dies with an unhandled one (Sekiro's top-level filter catches it, writes its report and ends with `__fastfail`, exit code `0xc0000409`) left only `[exc] ml811 code=e06d7363 ... nparams=4`.

## What it logs
`[exc] 0130 C++ throw (Microsoft): magic= object= throwinfo= image-base=`, then up to four `[exc] 0130   thrown type #n: "<mangled name>"` (the catchable types, most derived first; read from ThrowInfo -> CatchableTypeArray -> CatchableType.pType -> type_info name),
`[exc] 0130   object: <8 qwords>` and, for the object's 2nd to 4th qword when they look like pointers, the string they point to (`std::exception::what()` is the 2nd). Only the first four exceptions of that code per run (ml811's rate limit).

## Rebuild
`cp app/Madeira/arm64ec-windows/ntdll.dll $F4_BUILD_ROOT/backup-ntdll-before-0130.dll; bash vendor/Madeira/build/wine-pe/build-ntdll.sh`, then copy `vendor/Madeira/app/Madeira/arm64ec-windows/ntdll.dll` to `$F4_BUILD_ROOT/ec-out/ntdll.dll` and run `tools/stage_runtime.sh` (the unix library stays whatever the branch uses: on `experimental` gl-lib-0119).
