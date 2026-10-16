# 0042 - guest stack around RSP at a fault (diagnostic)

Black Ops 3's failed export lookup (see 0041) takes a function name the log does not show; protected code builds such strings on the stack. `signal_arm64_ios.c`: once per run, `[x86_code] stack <addr>: <hex>` for 0x800 bytes below and 0xa00 above the guest RSP at the first unhandled fault. Logging only.
