# 0002: DXMT air_tessellation.metal vs Metal toolchain 32023 (Xcode 27)
The internal intrinsic `__metal_atomic_fetch_add_explicit` gained a 5th `flags` argument; `research/dxmt/src/airconv/shaders/air_tessellation.metal:153` passes 4.
Applied at build time to a COPY (`tools/build_dxmt_shader_headers.sh`), appending `, __METAL_MEMORY_FLAGS_NONE__`. The submodule is untouched. Semantics unchanged (flags NONE).
Also: build/dxmt-ios/build.sh does not generate air_msad.h / air_samplepos.h / air_tessellation.h; that script does (same metal -> xxd chain as DXMT's meson).
