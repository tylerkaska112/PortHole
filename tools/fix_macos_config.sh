#!/bin/bash
# Make the freshly configured wine/build-macos/include/config.h match the one the iOS-side libs were originally built with
# (diff against the old working tree: exactly these three lines). Needed because configure on this Mac finds no macOS GnuTLS, which compiles
# bcrypt/gnutls.c and secur32/schannel_gnutls.c to nothing (-> undefined bcrypt_unix_call_funcs / secur32_unix_call_funcs at link). The iOS GnuTLS is static (toolchains/gnutls-ios).
# Also pipe2: the old tree had it undefined for the iOS target.
set -eu
C="$(cd "$(dirname "$0")/../vendor/Madeira/wine/build-macos/include" && pwd)/config.h"
sed -i '' \
  -e 's|^/\* #undef HAVE_GNUTLS_CIPHER_INIT \*/|#define HAVE_GNUTLS_CIPHER_INIT 1|' \
  -e 's|^/\* #undef SONAME_LIBGNUTLS \*/|#define SONAME_LIBGNUTLS "libgnutls.30.dylib"|' \
  -e 's|^#define HAVE_PIPE2 1|/* #undef HAVE_PIPE2 */|' "$C"
grep -n "HAVE_GNUTLS_CIPHER_INIT\|SONAME_LIBGNUTLS\|HAVE_PIPE2" "$C"
