#!/bin/bash
# Host test for patch 0020's relocation block index. usage: app/Tests/Reloc/run.sh
set -eu
cd "$(dirname "$0")"
OUT=$(mktemp -d)
cc -O2 -Wall -o "$OUT/t" reloc_index_test.c
"$OUT/t"
