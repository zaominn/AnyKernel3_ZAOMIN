# ZAOMIN Kernel Installer

ZAOMIN's private-profile flash package separates device/product behavior from
the upstream AnyKernel3 engine:

- `anykernel.sh` declares the boot-image operation and ZAOMIN profile.
- `tools/zaominn-profile.sh` owns serial-lock preparation, safety checks and
  optional module installation.
- `tools/ak3-core.sh` remains the licensed AnyKernel3 engine by osm0sis.

The split preserves the existing self-use configuration and installer output;
it does not add the ZAOMI-only Re-Kernel bundle behavior.
