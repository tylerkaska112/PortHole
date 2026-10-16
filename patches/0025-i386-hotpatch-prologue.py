#!/usr/bin/env python3
"""0025: give the 32-bit system DLLs Windows' hot-patch prologue.

Wine's i386 PE builds start most exported functions with `66 90` (xchg ax,ax, a two-byte no-op) behind five 0xCC padding bytes.
Windows' own x86 DLLs use `8b ff` (mov edi,edi) in the same layout, and hook libraries written for Windows commonly look for exactly that.
The two are equivalent no-ops (no register or flag changes). This swaps them at the entry point of every exported function that begins `66 90`.

    patches/0025-i386-hotpatch-prologue.py <vendor i386-windows folder> <output folder> [dll ...]
"""
import struct, sys, os

def patch(src, dst):
    d = bytearray(open(src, 'rb').read())
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    nsec, opt = struct.unpack_from('<H', d, pe + 6)[0], struct.unpack_from('<H', d, pe + 20)[0]
    assert struct.unpack_from('<H', d, pe + 24)[0] == 0x10b, 'not a PE32 image'
    sec = pe + 24 + opt
    secs = [struct.unpack_from('<8sIIII', d, sec + i * 40) for i in range(nsec)]
    def r2o(rva):
        for n, vs, va, rs, rp in secs:
            if va <= rva < va + max(vs, rs): return rva - va + rp
        return None
    exp_rva, exp_sz = struct.unpack_from('<II', d, pe + 24 + 96)
    e = r2o(exp_rva)
    nfun, nnames, afun, anames, aord = struct.unpack_from('<IIIII', d, e + 20)
    swapped, seen = 0, set()
    for i in range(nnames):
        o = struct.unpack_from('<H', d, r2o(aord) + 2 * i)[0]
        f = struct.unpack_from('<I', d, r2o(afun) + 4 * o)[0]
        if exp_rva <= f < exp_rva + exp_sz or f in seen: continue      # a forwarder, or already done
        seen.add(f)
        off = r2o(f)
        if off and d[off:off + 2] == b'\x66\x90':
            d[off:off + 2] = b'\x8b\xff'; swapped += 1
    open(dst, 'wb').write(d)
    return swapped

if __name__ == '__main__':
    src_dir, out_dir = sys.argv[1], sys.argv[2]
    names = sys.argv[3:] or ['ntdll.dll', 'kernel32.dll', 'kernelbase.dll']
    os.makedirs(out_dir, exist_ok=True)
    for n in names:
        print(n, patch(os.path.join(src_dir, n), os.path.join(out_dir, n)), 'entry points changed')
