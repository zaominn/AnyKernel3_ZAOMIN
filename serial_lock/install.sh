#!/sbin/sh

serial_lock_extract_marker() {
  local image=$1 outdir=$2
  rm -rf "$outdir"
  mkdir -p "$outdir" || return 1
  cd "$outdir" || return 1
  "$AKHOME/tools/magiskboot" unpack -h "$image" >/dev/null 2>&1 || return 1
  [ -f ramdisk.cpio ] || return 1
  "$AKHOME/tools/magiskboot" cpio ramdisk.cpio \
    "extract serial_lock/.mismatch marker.out" >/dev/null 2>&1 || rm -f marker.out
  return 0
}
serial_lock_prepare() {
  local token slot init_block work base hook size got
  token=$(tr -d '\r\n' < "$AKHOME/serial_lock/build-token" 2>/dev/null)
  case "$token" in *[!0-9a-f]*|'') ui_print "- Invalid serial lock build token"; return 1 ;; esac
  [ ${#token} -eq 64 ] || { ui_print "- Invalid serial lock token length"; return 1; }
  [ -x "$AKHOME/tools/magiskboot" ] || { ui_print "- magiskboot is unavailable"; return 1; }
  [ -d /data/adb ] && [ -w /data/adb ] || { ui_print "- /data/adb is unavailable; refusing an unsafe serial-locked flash"; return 1; }

  slot=$SLOT
  case "$slot" in _a|_b) ;; *) ui_print "- Active slot is unavailable"; return 1 ;; esac
  init_block=/dev/block/by-name/init_boot$slot
  [ -b "$init_block" ] || init_block=/dev/block/bootdevice/by-name/init_boot$slot
  [ -b "$init_block" ] || { ui_print "- init_boot$slot was not found"; return 1; }

  work=$AKHOME/serial_lock_work
  rm -rf "$work"
  mkdir -p "$work" || return 1
  dd if="$init_block" of="$work/init_boot.img" bs=1048576 2>/dev/null || return 1
  [ -s "$work/init_boot.img" ] || return 1

  # A freshly flashed serial-locked kernel must always get one normal first
  # mismatch boot, so remove a marker left by an older build before flashing boot.
  serial_lock_extract_marker "$work/init_boot.img" "$work/check" || return 1
  if [ -s "$work/check/marker.out" ]; then
    ui_print "- Clearing stale serial-lock marker from init_boot$slot"
    cd "$work/check" || return 1
    "$AKHOME/tools/magiskboot" cpio ramdisk.cpio "rm serial_lock/.mismatch" >/dev/null 2>&1 || return 1
    "$AKHOME/tools/magiskboot" repack "$work/init_boot.img" "$work/init_boot-clean.img" >/dev/null 2>&1 || return 1
    [ -s "$work/init_boot-clean.img" ] || return 1
    dd if="$work/init_boot-clean.img" of="$init_block" bs=1048576 conv=fsync 2>/dev/null || return 1
    sync
    size=$(wc -c < "$work/init_boot-clean.img" 2>/dev/null)
    dd if="$init_block" of="$work/readback.img" bs="$size" count=1 2>/dev/null || return 1
    got=$(sha256sum "$work/readback.img" | awk '{print $1}')
    [ "$got" = "$(sha256sum "$work/init_boot-clean.img" | awk '{print $1}')" ] || return 1
    serial_lock_extract_marker "$work/readback.img" "$work/recheck" || return 1
    if [ -s "$work/recheck/marker.out" ]; then
      ui_print "- Stale marker still present after verification"
      return 1
    fi
  fi

  # This is a one-shot root boot script, not a KernelSU/Magisk module. Keep
  # runtime files out of /data/adb/modules so nothing appears in module lists.
  base=/data/adb/serial_lock_stage
  hook=/data/adb/post-fs-data.d/00-oplus-serial-lock-stage.sh
  rm -rf /data/adb/modules/oplus-serial-lock-stage
  rm -rf "$base"
  mkdir -p "$base" /data/adb/post-fs-data.d || return 1
  cp "$AKHOME/serial_lock/post-fs-data.sh" "$base/stage.sh" || return 1
  cp "$AKHOME/serial_lock/build-token" "$base/build-token" || return 1
  cp "$AKHOME/tools/magiskboot" "$base/magiskboot" || return 1
  printf '%s\n' '#!/system/bin/sh' \
    'exec /system/bin/sh /data/adb/serial_lock_stage/stage.sh' > "$hook" || return 1
  chmod 0700 "$base" || return 1
  chmod 0755 "$base/stage.sh" "$base/magiskboot" "$hook" || return 1
  chmod 0600 "$base/build-token" || return 1
  rm -rf "$work"
  cd "$AKHOME" || return 1
  ui_print "- Serial-lock one-shot init_boot helper installed (not a module)"
  return 0
}
