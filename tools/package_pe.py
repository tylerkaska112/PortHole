#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Porthole authors. See LICENSE.
"""Package a freshly built Wine ARM64EC PE module the way Madeira's bundled DLLs are laid out.

What the b79 bundle's 131 arm64ec-windows DLLs look like (measured, see logs/ and STATUS.md):
  * no DWARF sections (the linker's "/4", "/43", ... sections are gone) and SizeOfImage ends at the last real section
  * file length = SizeOfImage + k * 0x10000 with k in 1..6 (slack after the image; ntdll's script uses +0x50000)

This tool: drops trailing DWARF sections, recomputes SizeOfImage, clears the symbol-table pointer and checksum, and
zero-pads the file to SizeOfImage + SLACK. It refuses anything it does not fully understand. It does not touch code or data.

usage: package_pe.py IN.dll OUT.dll
"""
import struct, sys

SLACK = 0x60000  # the largest slack seen in the shipped bundle; extra zeros are harmless, too little is not known to be safe


def align(v, a):
    return (v + a - 1) // a * a


def main(src, dst):
    d = bytearray(open(src, 'rb').read())
    if d[:2] != b'MZ':
        raise SystemExit("not MZ")
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    if d[pe:pe + 4] != b'PE\0\0':
        raise SystemExit("not PE")
    machine, nsec = struct.unpack_from('<HH', d, pe + 4)
    if machine not in (0x8664, 0xA641):  # ARM64EC modules are tagged AMD64 (0x8664); the shipped bundle is too
        raise SystemExit("machine %#x is neither AMD64-tagged ARM64EC nor ARM64EC" % machine)
    optsz = struct.unpack_from('<H', d, pe + 20)[0]
    opt = pe + 24
    if struct.unpack_from('<H', d, opt)[0] != 0x20b:
        raise SystemExit("not PE32+")
    sect_align = struct.unpack_from('<I', d, opt + 32)[0]
    st = opt + optsz

    secs = []
    for i in range(nsec):
        o = st + 40 * i
        name = bytes(d[o:o + 8]).rstrip(b'\0').decode('latin1')
        vs, va, rs, rp = struct.unpack_from('<IIII', d, o + 8)
        secs.append(dict(o=o, name=name, vs=vs, va=va, rs=rs, rp=rp))

    def is_dwarf(n):
        return n.startswith('/') or n.startswith('.debug_')

    keep = [s for s in secs if not is_dwarf(s['name'])]
    drop = [s for s in secs if is_dwarf(s['name'])]
    # the dropped sections must be a contiguous tail of the table, after every real section
    if secs[:len(keep)] != keep:
        raise SystemExit("DWARF sections are not a pure tail of the section table; refusing")
    if not keep:
        raise SystemExit("no real sections")
    new_soi = align(keep[-1]['va'] + keep[-1]['vs'], sect_align)
    if drop and drop[0]['va'] < new_soi:
        raise SystemExit("a DWARF section overlaps the real image; refusing")

    # the base relocation directory and everything else the loader reads must live inside the kept image
    ndir = struct.unpack_from('<I', d, opt + 108)[0]
    for i in range(min(ndir, 16)):
        rva, size = struct.unpack_from('<II', d, opt + 112 + 8 * i)
        if i == 4:  # certificate table is a FILE offset, not an RVA
            continue
        if rva and rva + size > new_soi:
            raise SystemExit("data directory %d (rva %#x size %#x) lies in the removed region" % (i, rva, size))

    for s in drop:
        d[s['o']:s['o'] + 40] = b'\0' * 40
    struct.pack_into('<H', d, pe + 6, len(keep))
    struct.pack_into('<II', d, pe + 12, 0, 0)        # PointerToSymbolTable, NumberOfSymbols
    struct.pack_into('<I', d, opt + 56, new_soi)     # SizeOfImage
    struct.pack_into('<I', d, opt + 64, 0)           # CheckSum (the loader does not verify it for these modules)

    raw_end = max(s['rp'] + s['rs'] for s in keep)
    target = new_soi + SLACK
    if raw_end > target:
        raise SystemExit("real data ends at %#x, beyond the padded target %#x" % (raw_end, target))
    out = bytes(d[:raw_end]) + b'\0' * (target - raw_end)
    open(dst, 'wb').write(out)
    print("%s: %d -> %d bytes; sections %d -> %d; SizeOfImage %#x; slack %#x"
          % (dst, len(d), len(out), nsec, len(keep), new_soi, SLACK))


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
