### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers & GitHub @ Xiaomichael

### AnyKernel setup
# global properties
properties() { '
kernel.string=ZAOMIN Kernel Installer (AnyKernel3) | Build by ZAOMIN
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

# Import the licensed AnyKernel3 engine, then the ZAOMIN product layer.
. tools/ak3-core.sh
ZAOMINN_BUILDER=ZAOMIN
ZAOMINN_INSTALL_REKERNEL=0
. tools/zaominn-profile.sh
zaominn_prepare_flash

# boot install
split_boot
if [ -f "split_img/ramdisk.cpio" ]; then
    unpack_ramdisk
    write_boot
else
    flash_boot
fi
## end boot install
zaominn_install_bundled_modules
