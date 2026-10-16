# Vendored runtime glue
C/Objective-C bridges and the JIT-pool Swift helper (StikJITHelper) are Madeira's (github.com/willfaust/Madeira, GPL-3.0-or-later), taken from the user's
own archive `Madeira-20260924.tar.gz`. Only files with no mention of Iridium are vendored (`tools/vendor_glue.sh` refuses otherwise). No Madeira or Iridium UI is
included. Hashes: SHA256SUMS. Changes to these files must be made as numbered patches in ../../patches, not by editing here silently.
