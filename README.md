# AnyKernel3 Kernel Installer

This self-use flash package separates device/product behavior from
the upstream AnyKernel3 engine:

- `anykernel.sh` declares the boot-image operation and installer profile.
- `tools/installer-profile.sh` owns serial-lock preparation, safety checks and
  optional module installation.
- `tools/ak3-core.sh` remains the licensed AnyKernel3 engine by osm0sis.

The split preserves the existing self-use configuration and installer output,
including installation of a bundled Re-Kernel module when present.
