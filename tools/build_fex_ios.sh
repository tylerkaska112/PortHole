#!/bin/bash
# Same as vendor/Madeira/build/fex-ios/build.sh, plus -DCMAKE_SYSTEM_PROCESSOR=arm64 and -DTUNE_CPU=cortex-a78 (both in the user's old working cache;
# (GitHub HEAD only, and it still fails there: adding -DFEX_IOS_HOST via C/CXX/ASM flags gets past Core.cpp but Arm64.cpp then needs Windows APIs.)
# FEX_IOS_HOST note: Core.cpp's iOS probes use IosFfsBypassLog/IosCbEntryLog unguarded; their externs are only declared under FEX_IOS_HOST (build/fex-wow64/build.sh
# passes it the same way, via the compiler flags). Without it the pinned FEX does not compile for iOS.
# without TUNE_CPU FEX tries to read /proc/cpuinfo, which macOS lacks).
# Why: that script's configure is "reconstructed" and omits it; CMake 4.x then leaves the processor empty and FEX's CMakeLists.txt:115 aborts
# ("Unsupported processor type"). The user's old working build cache has CMAKE_SYSTEM_PROCESSOR=arm64. Vendor tree stays unmodified.
set -eu
R="${MADEIRA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../vendor/Madeira" && pwd)}"
B="$R/FEX/build-ios"
if [ ! -f "$B/CMakeCache.txt" ]; then
    cmake -S "$R/FEX" -B "$B" -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DTUNE_CPU=cortex-a78 -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF -DBUILD_THUNKS=OFF -DBUILD_FEXCONFIG=OFF -DBUILD_FEX_LINUX_TESTS=OFF \
        -DENABLE_FEX_ALLOCATOR=OFF -DENABLE_ASSERTIONS=OFF -DENABLE_CLANG_THUNKS=ON -DENABLE_CCACHE=ON
fi
cmake --build "$B" --target FEXCore FEXCore_Base -j6
ls "$B/FEXCore/Source/"*.a
