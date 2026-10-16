#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Porthole authors. See LICENSE.
"""Independent SRP-6a client for Apple's pair-setup variant (SHA-512, 3072-bit group, g=5), used to test the Swift host.
usage: srp_client.py PIN SALT_HEX B_HEX   -> prints A_hex M1_hex K_hex M2_hex"""
import sys, hashlib, secrets
import re, os
_src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../Sources/Pairing/SRP3072.swift')).read()
N = int(re.search(r'primeHex =\s*"([0-9a-f]+)"', _src).group(1), 16)
g = 5
H = lambda *parts: hashlib.sha512(b''.join(parts)).digest()
def b(n): 
    return n.to_bytes((n.bit_length()+7)//8 or 1, 'big')
def pad(x): return x.rjust(384, b'\0')
pin, salt, B = sys.argv[1].encode(), bytes.fromhex(sys.argv[2]), int(sys.argv[3], 16)
user = b'Pair-Setup'
k = int.from_bytes(H(b(N), pad(b(g))), 'big')
x = int.from_bytes(H(salt, H(user, b':', pin)), 'big')
a = secrets.randbits(256)
A = pow(g, a, N)
u = int.from_bytes(H(b(A), b(B)), 'big')
S = pow((B - k * pow(g, x, N)) % N, a + u * x, N)
K = H(b(S))
hng = bytes(p ^ q for p, q in zip(H(g.to_bytes(1,'big')), H(b(N))))
M1 = H(hng, H(user), salt, pad(b(A)), pad(b(B)), K)
M2 = H(b(A), M1, K)
print(b(A).hex(), M1.hex(), K.hex(), M2.hex())
