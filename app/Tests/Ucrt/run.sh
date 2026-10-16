#!/bin/bash
# Compiles patch 0084's path rule (ios_app_ucrt_alt_name, taken verbatim from vendor/Madeira/wine/dlls/ntdll/unix/file.c) for the Mac and checks which paths it redirects.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../../../vendor/Madeira/wine/dlls/ntdll/unix/file.c"
OUT="$(mktemp -d)"
python3 - "$SRC" "$OUT/rule.inc" <<'PY'
import sys,re
s=open(sys.argv[1]).read()
a=s.index('static BOOL ios_app_ucrt_alt_name')
b=s.index('\n}\n',a)+3
open(sys.argv[2],'w').write(s[a:b])
PY
cat > "$OUT/t.c" <<'C'
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <wchar.h>
#include <stdint.h>
typedef uint16_t WCHAR; typedef int BOOL; typedef struct { uint16_t Length, MaximumLength; WCHAR *Buffer; } UNICODE_STRING;
#define TRUE 1
#define FALSE 0
#define MAX_PATH 260
#include "rule.inc"
static int fails;
static void check(const char *path, int expect) {
    WCHAR in[300], buf[300]; UNICODE_STRING name, alt; size_t n = strlen(path);
    for (size_t i = 0; i < n; i++) in[i] = (unsigned char)path[i];
    name.Buffer = in; name.Length = n * 2; name.MaximumLength = name.Length + 2;
    int r = ios_app_ucrt_alt_name(&name, buf, &alt);
    int ok = r == expect;
    if (r) { char out[300]; for (unsigned i = 0; i < alt.Length / 2; i++) out[i] = (char)alt.Buffer[i]; out[alt.Length / 2] = 0; ok = ok && !strcmp(out, "\\??\\C:\\windows\\sysx64\\ucrtbase.dll"); }
    printf("%s  %s -> %s\n", ok ? "ok  " : "FAIL", path, r ? "sysx64" : "(untouched)");
    if (!ok) fails++;
}
int main(void) {
    check("\\??\\C:\\Program Files\\Rockstar Games\\Launcher\\ucrtbase.dll", 1);
    check("\\??\\C:\\Program Files (x86)\\Steam\\steamapps\\common\\Game\\UCRTBASE.DLL", 1);
    check("\\??\\C:\\windows\\system32\\ucrtbase.dll", 0);
    check("\\??\\C:\\Windows\\System32\\ucrtbase.dll", 0);
    check("\\??\\C:\\windows\\sysx64\\ucrtbase.dll", 0);
    check("\\??\\C:\\windows\\syswow64\\ucrtbase.dll", 0);
    check("\\??\\C:\\Program Files\\Game\\ucrtbase_enclave.dll", 0);
    check("\\??\\C:\\Program Files\\Game\\myucrtbase.dll", 0);
    check("\\??\\C:\\Program Files\\Game\\ucrtbase.dll.bak", 0);
    check("\\??\\C:\\ucrtbase.dll", 1);
    setenv("MADEIRA_APP_LOCAL_UCRT", "1", 1);
    check("\\??\\C:\\Program Files\\Rockstar Games\\Launcher\\ucrtbase.dll", 0);
    if (fails) { printf("%d FAILED\n", fails); return 1; }
    printf("All ucrt path checks passed.\n"); return 0;
}
C
cc -std=gnu11 -o "$OUT/t" "$OUT/t.c" -I"$OUT" && "$OUT/t"
rm -rf "$OUT"
