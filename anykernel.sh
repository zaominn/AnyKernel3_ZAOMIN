### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers & GitHub @ Xiaomichael

### AnyKernel setup
# global properties
properties() { '
kernel.string=AnyKernel3 by KernelSU Developers | Build by ZAOMIN
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

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

ui_print "内核构建者: ZAOMIN"

# Recover inode flags left by older NoMount builds before KernelSU gets a chance
# to replace its userspace daemon.  Do not rely on a recovery-provided chattr:
# AnyKernel already ships a known busybox, so use that implementation directly
# and verify that both immutable and append-only flags are really gone.
clear_legacy_ksud_attrs() {
    local bb target attrs real
    bb="$AKHOME/tools/busybox"
    chmod 0755 "$bb" 2>/dev/null
    for target in /data/adb/ksud /data/adb/ksu/bin/ksu_susfs; do
        [ -e "$target" ] || continue
        real=$("$bb" readlink -f "$target" 2>/dev/null)
        [ -n "$real" ] || real="$target"
        "$bb" chattr -ia "$real" 2>/dev/null
        attrs=$("$bb" lsattr -d "$real" 2>/dev/null | "$bb" awk '{print $1}')
        case "$attrs" in
            *i*|*a*) abort "Unable to clear legacy ksud inode flags; boot was not flashed." ;;
        esac
    done
}
clear_legacy_ksud_attrs

# Resolving occasional file system I/O latency issues which may cause binary execution exceptions
sync
sleep 0.5
chmod -R 755 $AKHOME/tools

# Build-specific staged serial lock support. Generic packages without a
# serial_lock/build-token keep the original AnyKernel behaviour.
if [ -f "$AKHOME/serial_lock/build-token" ]; then
    . "$AKHOME/serial_lock/install.sh"
    serial_lock_prepare || abort "Serial lock preparation failed. Boot was not flashed."
fi

# boot install
split_boot
if [ -f "split_img/ramdisk.cpio" ]; then
    unpack_ramdisk
    write_boot
else
    flash_boot
fi
## end boot install
# 优先选择模块路径
if [ -f "$AKHOME/zram.zip" ]; then
    MODULE_PATH="$AKHOME/zram.zip"
    KSUD_PATH="/data/adb/ksud"
    if [ -f "$KSUD_PATH" ]; then
        ui_print "Installing zram Module..."
        /data/adb/ksud module install "$MODULE_PATH"
        ui_print "Installation Complete!"
    else
        ui_print "KSUD Not Found, skipping installation..."
    fi
else
    ui_print "ZRAM module Not Found, skipping ZRAM module installation..."
fi
if [ -f "$AKHOME/kpn.zip" ]; then
    MODULE_PATH="$AKHOME/kpn.zip"
    KSUD_PATH="/data/adb/ksud"
    if [ -f "$KSUD_PATH" ]; then
        ui_print "Installing KP-N Module..."
        /data/adb/ksud module install "$MODULE_PATH"
        ui_print "Installation Complete!"
    else
        ui_print "KSUD Not Found, skipping installation..."
    fi
else
    ui_print "KP-N module Not Found, skipping KP-N module installation..."
fi
