# 0132 The Microsoft C++ throw decoder also lists the text on the stack (diagnostic, log only)

0.50.315 log (Sekiro): `std::runtime_error: "bad locale name"` again and NO `[locale] 0131` line, so the failing `std::locale(name)` call is not served by Wine's ucrtbase: the program links its C and C++ runtime statically
(its own `setlocale` over kernelbase's NLS functions). The name it asked for is therefore only in the program's memory. 0132 adds to 0130's output: `[exc] 0132 stack+0xN text "..."` for printable runs (4+ chars) in the
4 KB above the exception's stack pointer (an inline small string holds the name there) and `[exc] 0132 stack+0xN -> <ptr> "..."` for the short strings that stack pointers lead to. Up to 80 lines, only with the first four exceptions of that code per run.
Rebuild: as 0130 (`build/wine-pe/build-ntdll.sh`, copy to `ec-out/ntdll.dll`).
