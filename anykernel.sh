### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers & GitHub @ Xiaomichael

### AnyKernel setup
# global properties
properties() { '
kernel.string=AnyKernel3 Kernel Installer
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
## boot shell variables
BLOCK=boot
IS_SLOT_DEVICE=auto
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto
NO_MAGISK_CHECK=1

# Import the licensed AnyKernel3 engine, then the installer profile.
. tools/ak3-core.sh
INSTALLER_INSTALL_REKERNEL=0
. tools/installer-profile.sh
installer_prepare_flash

# boot install
split_boot
if [ -f "split_img/ramdisk.cpio" ]; then
    unpack_ramdisk
    write_boot
else
    flash_boot
fi
## end boot install
installer_install_bundled_modules
