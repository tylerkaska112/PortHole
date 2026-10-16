#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Porthole authors. See LICENSE.
"""Remove the build machine's user name from a built app, and report anything of the builder's that is left.

Compilers record the absolute path of every source file (assert messages in the Windows DLLs, debug-map entries in the executable,
shader modules). Those paths contain the builder's login name. This rewrites the name inside such paths to a same-length neutral
one, in place, so nothing moves or changes size; the paths are only ever read by debuggers.

    tools/scrub_paths.py <dir> [--audit] [--strict] [--allow <text> ...]

  --audit    only report, change nothing
  --strict   exit 1 if the builder's login name, host name (or anything in $SCRUB_ALSO) still appears anywhere (use on a public build)
  --allow    comma-separated text that may legitimately remain (a private build's own bundle id, server address, ...)
"""
import getpass, os, re, socket, sys
from pathlib import Path

args = sys.argv[1:]
audit_only = "--audit" in args
strict = "--strict" in args
allow = [t.encode() for i, a in enumerate(args) if a == "--allow" and i + 1 < len(args) for t in args[i + 1].split(",") if t]
roots = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] != "--allow")]
if len(roots) != 1:
    sys.exit(__doc__)
root = Path(roots[0])

user = getpass.getuser().encode()
neutral = (b"buildagent" + b"x" * len(user))[: len(user)]
# the user name as it appears inside a path, in the spellings compilers use
spellings = [(b"/Users/", b"/"), (b"-Users-", b"-"), (b"?1Users?1", b"?1"), (b"\\Users\\", b"\\"), (b"%2FUsers%2F", b"%2F"), (b"/home/", b"/")]
rewrites = [(prefix + user, prefix + neutral) for prefix, _ in spellings]
# External drives the build lives on are part of the machine's layout too: /Volumes/<name> becomes /Volumes/vvvv...
volumes = [v.encode() for v in os.environ.get("SCRUB_VOLUMES", "").split(",") if v]
rewrites += [(b"/Volumes/" + v, b"/Volumes/" + b"v" * len(v)) for v in volumes]

# The project folder's name appears in the same recorded paths (…/Desktop/<project>/vendor/…): rewritten to a same-length neutral name (SCRUB_PROJECTS, comma separated, from tools/local.env).
projects = [t.encode() for t in os.environ.get("SCRUB_PROJECTS", "").split(",") if t]
def neutral_project(name: bytes) -> bytes:
    base = b"Porthole-src-"
    return (base * (len(name) // len(base) + 1))[: len(name)]
rewrites += [(b"/" + name, b"/" + neutral_project(name)) for name in projects]
rewrites += [(b"\\" + name, b"\\" + neutral_project(name)) for name in projects]
rewrites += [(b"-" + name, b"-" + neutral_project(name)) for name in projects]
extra = [t.encode() for t in os.environ.get("SCRUB_ALSO", "").split(",") if t]   # e.g. your e-mail address, from tools/local.env
identity = [user, socket.gethostname().split(".")[0].encode(), *extra, *[b"/Volumes/" + v for v in volumes]]
identity = [i for i in identity if len(i) >= 4 and i.lower() != b"localhost"]

def bit_rewrite(data: bytes, old: bytes, new: bytes) -> tuple[bytes, int]:
    """LLVM bitcode writes some strings (a module's source file name) as 7- or 8-bit fields packed with no byte alignment, so
    they never show up as plain text. Find `old` at any bit offset, least-significant bit first, and overwrite it in place."""
    assert len(old) == len(new)
    out = bytearray(data)
    count = 0
    for width in (7, 8):
        for shift in range(8):
            bits = [0] * shift
            for ch in old:
                bits += [(ch >> i) & 1 for i in range(width)]
            # the whole bytes the pattern covers are the search key; the ragged edges are checked afterwards
            first = (shift + 7) // 8 if shift else 0
            total = shift + len(old) * width
            last = total // 8
            if last - first < 8:
                continue
            key = bytearray()
            for b in range(first, last):
                key.append(sum(bits[b * 8 + i] << i for i in range(8)))
            at = bytes(out).find(bytes(key))
            while at >= 0:
                start = at - first
                nbytes = (total + 7) // 8
                if start >= 0 and start + nbytes <= len(out):
                    window = int.from_bytes(out[start:start + nbytes], "little")
                    pattern = sum(bit << i for i, bit in enumerate(bits))
                    mask = ((1 << (len(old) * width)) - 1) << shift
                    if (window & mask) == (pattern & mask):
                        replacement = [0] * shift
                        for ch in new:
                            replacement += [(ch >> i) & 1 for i in range(width)]
                        value = sum(bit << i for i, bit in enumerate(replacement))
                        window = (window & ~mask) | (value & mask)
                        out[start:start + nbytes] = window.to_bytes(nbytes, "little")
                        count += 1
                at = bytes(out).find(bytes(key), at + 1)
    return bytes(out), count


changed_files = rewritten = 0
leftovers: dict[str, list[bytes]] = {}
for path in sorted(p for p in root.rglob("*") if p.is_file() and not p.is_symlink()):
    data = path.read_bytes()
    new = data
    for old, repl in rewrites:
        if old in new:
            rewritten += new.count(old)
            new = new.replace(old, repl)
    if b"BC\xc0\xde" in new:
        new, n = bit_rewrite(new, b"/Users/" + user, b"/Users/" + neutral)
        rewritten += n
    if new != data and not audit_only:
        path.write_bytes(new)
        changed_files += 1
    remaining = new if not audit_only else data
    found = []
    for needle in identity:
        for m in re.finditer(re.escape(needle), remaining, re.IGNORECASE):
            context = remaining[max(0, m.start() - 24): m.end() + 24]
            if any(a in context for a in allow):
                continue
            found.append(context)
            break
    if found:
        leftovers[str(path.relative_to(root))] = found

print(f"{'would rewrite' if audit_only else 'rewrote'} {rewritten} path(s) in {changed_files if not audit_only else '?'} file(s)")
if leftovers:
    print(f"still mentions the builder in {len(leftovers)} file(s):")
    for name, ctx in list(leftovers.items())[:25]:
        print(f"  {name}: {ctx[0]!r}")
    if len(leftovers) > 25:
        print(f"  … and {len(leftovers) - 25} more")
    if strict:
        sys.exit(1)
else:
    print("nothing of the builder's is left")
