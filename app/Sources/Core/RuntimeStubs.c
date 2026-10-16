// Two symbols the runtime glue expects from Madeira's FEXBridge.mm. We do not link FEXCore into the app (FEX runs as the xtajit64.dll PE module),
// so these are provided here. Both are tiny and have no FEX dependency.
#include <stdint.h>
#include <stdlib.h>
#include <libkern/OSCacheControl.h>

// icache invalidation builtin; Apple's ld has no compiler-rt copy.
void __clear_cache(void *start, void *end) {
    sys_icache_invalidate(start, (size_t)((char *)end - (char *)start));
}

// RX->RW distance of the dual-mapped JIT pool. WineProcessBridge publishes it to xtajit64.dll as MADEIRA_JIT_WRITE_OFFSET.
// FEXBridge.mm computed it from its own pool variables; we read the same pool the Core published in WINE_IOS_JIT_RX / WINE_IOS_JIT_RW (hex).
int64_t fex_get_jit_write_offset(void) {
    const char *rx = getenv("WINE_IOS_JIT_RX"), *rw = getenv("WINE_IOS_JIT_RW");
    if (!rx || !rw) return 0;
    uintptr_t a = (uintptr_t)strtoull(rx, NULL, 16), b = (uintptr_t)strtoull(rw, NULL, 16);
    return (int64_t)((intptr_t)b - (intptr_t)a);
}
