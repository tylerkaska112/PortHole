#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Patch 0015, binary form. Applies the guard described in 0015-fex-context-gone-at-exit.md to one of the xtajit64.dll files it knows
# (KNOWN below: the one that shipped up to engine 40d5e74-r4, and Madeira's rebuilds from FEX be778d7 and 3bec2ac), and writes the patched copy.
# It refuses any other input, so the result is the same bytes every time.
#
#   python3 patches/0015-xtajit64-context-guard.py <xtajit64.dll in> <xtajit64.dll out>
#
# What it changes (two places, nothing else):
#   1. The first instruction of FEX::Windows::InvalidationTracker::InvalidateIntervalInternal (RVA 0x12b9b4, `stp x19, x20, [sp, #-0x40]!`)
#      becomes a branch into the unused tail of .text.
#   2. There, at RVA 0x209d20 (inside .text's last page, zero padding), a 6-instruction guard:
#        ldr x16, [x0, #0x50]      ; this->CTX, the FEXCore context
#        ldr x16, [x16]            ; its first word, the vtable: zero once the context is destroyed
#        cbz x16, return           ; context gone: nothing to invalidate, leave the function untouched
#        stp x19, x20, [sp, #-0x40]!   ; the instruction that was displaced
#        b   <function + 4>
#      return: ret
import hashlib, struct, sys

# Known inputs: prefix of the file's SHA-256 -> where the function is and what its prologue and CTX member offset are.
#   dc5c980c...  the xtajit64.dll that shipped up to engine 40d5e74-r2 (FEX 26859e1): CTX at this+0x50
#   65d66511...  Madeira's rebuild from FEX be778d7 (Oct 2026): its InvalidationTracker gained an 8-byte owner field, so CTX is at this+0x58
KNOWN = {
    "dc5c980c28829227": dict(func=0x12B9B4, cave=0x209D20, ctx=0x50, displaced=0xA9BC53F3),   # stp x19, x20, [sp, #-0x40]!
    "65d66511114aa368": dict(func=0x12C188, cave=0x20AD28, ctx=0x58, displaced=0xA9BD53F3),   # stp x19, x20, [sp, #-0x30]!
    # 6c79f366...  Madeira's rebuild from FEX 3bec2ac (Oct 2026, Wine Mono changes): same layout, the function is byte-identical up to its ret and at the
    #              same RVA (checked against the previous build), so the same guard applies
    "6c79f366fb9aad3b": dict(func=0x12C188, cave=0x20AD28, ctx=0x58, displaced=0xA9BD53F3),
}
# FUNC: InvalidationTracker::InvalidateIntervalInternal(uint64, uint64). CAVE: zero padding after the last function in .text.

def b(from_rva, to_rva):
    delta = (to_rva - from_rva) // 4
    assert -(1 << 25) <= delta < (1 << 25)
    return 0x14000000 | (delta & 0x03FFFFFF)

def main(src, dst):
    data = bytearray(open(src, "rb").read())
    known = KNOWN.get(hashlib.sha256(data).hexdigest()[:16])
    if not known:
        sys.exit("this is not an xtajit64.dll the patch was written for (sha256 starts %s)" % hashlib.sha256(data).hexdigest()[:16])
    FUNC_RVA, CAVE_RVA, DISPLACED = known["func"], known["cave"], known["displaced"]
    LDR_CTX = 0xF9400010 | ((known["ctx"] // 8) << 10)   # ldr x16, [x0, #ctx]
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    nsec = struct.unpack_from("<H", data, pe + 6)[0]; opt = struct.unpack_from("<H", data, pe + 20)[0]
    sec = pe + 24 + opt
    text = None
    for i in range(nsec):
        name, vsize, va, rawsize, rawoff = struct.unpack_from("<8sIIII", data, sec + i * 40)
        if name.rstrip(b"\0") == b".text": text = (vsize, va, rawsize, rawoff)
    vsize, va, rawsize, rawoff = text
    assert rawoff == va, "file offset == RVA is assumed"
    assert va + vsize <= CAVE_RVA and CAVE_RVA + 24 <= va + rawsize, "the guard must sit in .text's own padding"
    assert struct.unpack_from("<I", data, FUNC_RVA)[0] == DISPLACED, "unexpected first instruction"
    assert data[CAVE_RVA:CAVE_RVA + 24] == bytes(24), "the padding is not empty"
    guard = [
        LDR_CTX,                             # ldr x16, [x0, #ctx]: this->CTX, the FEXCore context
        0xF9400210,                          # ldr x16, [x16]
        0xB4000070,                          # cbz x16, +12 (the ret below)
        DISPLACED,                           # the displaced first instruction (stp x19, x20, [sp, #-N]!)
        b(CAVE_RVA + 16, FUNC_RVA + 4),      # b function+4
        0xD65F03C0,                          # ret
    ]
    for n, word in enumerate(guard): struct.pack_into("<I", data, CAVE_RVA + 4 * n, word)
    struct.pack_into("<I", data, FUNC_RVA, b(FUNC_RVA, CAVE_RVA))
    open(dst, "wb").write(data)
    print("patched %s -> %s (sha256 %s)" % (src, dst, hashlib.sha256(data).hexdigest()[:16]))

if __name__ == "__main__":
    if len(sys.argv) != 3: sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
