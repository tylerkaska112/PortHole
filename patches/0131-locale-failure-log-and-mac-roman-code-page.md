# 0131 Name the locale that failed, and ship code page 10000 (Mac Roman)

## Why (Sekiro, 0.50.314 log, 08:07)
0130 named the fatal exception: `std::runtime_error` with the text `bad locale name`. The MSVC STL throws that when `setlocale`/`_create_locale` returns NULL for the name a program hands to `std::locale(...)`. Nothing said which name or why.
The same logs show `NtCreateFile ... c_10000.nls` failing (`0xc0000034`) fifteen times early in a run and `[nls-getptr] type=11 id=10000`: code page 10000 (Mac Roman, `CP_MACCP`) is requested and `Porthole.app/nls` ships only 437, 1252, 20127 and 28591.

## What it does
1. `wine/dlls/msvcrt/locale.c` (built into `ucrtbase.dll`): `create_locinfo_logged` wraps `create_locinfo` and logs `[locale] 0131 category N name "..." failed (ACP, OEMCP, user locale)` for the first 24 failures (`err:...` channel).
   Rebuilt with `DEST=/tmp/ucrt0131 bash vendor/Madeira/build/wine-pe/build-modules.sh ucrtbase` (same size as the shipped file, 1507328 bytes), installed as `$F4_BUILD_ROOT/ec-out/ucrtbase.dll` (the pinned file in the farm is untouched).
2. `nls/c_10000.nls` from Wine's own `nls/` directory (66082 bytes, copy in `patches/0131-c_10000.nls`) is added to `vendor/Madeira/app/Madeira/nls`, so the code page exists.

## Not verified / open
Whether the missing code page is what makes `setlocale` fail. If the log names a locale and the failure remains with the file present, the cause is the name (for example a language-country form Wine's table does not know).
