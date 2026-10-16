# 0134 Ship every code page table Wine provides (nls/c_*.nls)

0.50.317 log (Sekiro), `[exc] 0132`: the text on the stack at the fatal `std::runtime_error("bad locale name")` is `"Japanese"` (an inline string and the pointers to it): the program calls `std::locale("Japanese")`.
Its statically linked C runtime resolves the Windows language name to the locale ja-JP and then needs the locale's ANSI code page, 932 (Shift-JIS); `IsValidCodePage`/`GetCPInfo(932)` fail without `c_932.nls`, so `setlocale` returns NULL.
`Porthole.app/nls` shipped only 437, 1252, 20127, 28591 (and 10000 since 0.50.315). 0.50.318 adds every `c_*.nls` of Wine's own `nls/` directory (68 files, 5.7 MB; 932, 936, 949, 950, 874, 1250-1258 ...):
`cp -n vendor/Madeira/wine/nls/c_*.nls vendor/Madeira/app/Madeira/nls/` (the files are Wine's, nothing generated; `nls/` is a resource folder of the app).
