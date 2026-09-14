#!/sbin/sh

# ZAOMINN product layer. The generic partition/ramdisk engine remains in
# ak3-core.sh so upstream attribution and updateability stay intact.

zaominn_clear_legacy_ksud_attrs() {
    local bb target attrs real
    bb="$AKHOME/tools/busybox"
    chmod 0755 "$bb" 2>/dev/null
    for target in /data/adb/ksud /data/adb/ksu/bin/ksu_susfs; do
        [ -e "$target" ] || continue
        real=$("$bb" readlink -f "$target" 2>/dev/null)
        [ -n "$real" ] || real="$target"
        "$bb" chattr -ia "$real" 2>/dev/null \
            || abort "Unable to clear legacy ksud inode flags; boot was not flashed."
        attrs=$("$bb" lsattr -d "$real" 2>/dev/null | "$bb" awk '{print $1}')
        [ -n "$attrs" ] \
            || abort "Unable to verify legacy ksud inode flags; boot was not flashed."
        case "$attrs" in
            *i*|*a*) abort "Unable to clear legacy ksud inode flags; boot was not flashed." ;;
        esac
    done
}

zaominn_prepare_flash() {
    ui_print " "
    ui_print "ZAOMIN Kernel Installer"
    ui_print "内核构建者: $ZAOMINN_BUILDER"
    ui_print " "
    zaominn_clear_legacy_ksud_attrs
    sync
    sleep 0.5
    chmod -R 0755 "$AKHOME/tools"
    if [ -f "$AKHOME/serial_lock/build-token" ]; then
        . "$AKHOME/serial_lock/install.sh"
        serial_lock_prepare \
            || abort "Serial lock preparation failed. Boot was not flashed."
    fi
}

zaominn_install_module() {
    local archive label
    archive=$1
    label=$2
    [ -f "$AKHOME/$archive" ] || {
        ui_print "$label module not bundled, skipping..."
        return 0
    }
    [ -f /data/adb/ksud ] || {
        ui_print "KSUD not found; skipping $label module installation..."
        return 0
    }
    ui_print "Installing $label module..."
    /data/adb/ksud module install "$AKHOME/$archive" \
        || abort "$label module installation failed after boot flash."
    ui_print "$label module installation complete."
}

zaominn_install_bundled_modules() {
    zaominn_install_module zram.zip ZRAM
    zaominn_install_module kpn.zip KP-N
    if [ "${ZAOMINN_INSTALL_REKERNEL:-0}" = 1 ]; then
        zaominn_install_module rekernel.zip Re-Kernel
    fi
}
