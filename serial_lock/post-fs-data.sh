#!/system/bin/sh

STATE=/proc/oplus_serial_lock
BASE=/tmp/serial_lock_stage
MAGISKBOOT=${SERIAL_LOCK_MAGISKBOOT:-/data/adb/.serial_lock_magiskboot}
HOOK=/data/adb/service.d/service_log.sh
LOCK=$BASE/lock
WORK=$BASE/work.$$
LOG=$BASE/stage.log
finished=0

cleanup() {
  rm -rf "$BASE"
  if [ "$finished" = 1 ]; then
    rm -f "$HOOK" "$MAGISKBOOT"
  fi
}
die() {
  echo "$*"
  exit 1
}
trap cleanup EXIT
trap 'exit 1' INT TERM

mkdir -p "$BASE" || exit 1
chmod 0700 "$BASE" 2>/dev/null || exit 1
exec >>"$LOG" 2>&1

state=$(cat "$STATE" 2>/dev/null) || die "serial lock state unavailable"
case "$state" in
  verified|mismatch-pending|mismatch-armed) ;;
  *) die "unknown serial lock state: $state" ;;
esac

chmod 0700 "$MAGISKBOOT" 2>/dev/null || die "magiskboot permissions unavailable"
[ -x "$MAGISKBOOT" ] || die "magiskboot unavailable"
mkdir "$LOCK" 2>/dev/null || die "another staging process owns the lock"

slot=$(getprop ro.boot.slot_suffix 2>/dev/null)
case "$slot" in
  _a|_b) ;;
  *) die "invalid slot suffix: $slot" ;;
esac
block=/dev/block/by-name/init_boot$slot
[ -b "$block" ] || block=/dev/block/bootdevice/by-name/init_boot$slot
[ -b "$block" ] || die "init_boot block not found"

mkdir -p "$WORK/patch" "$WORK/verify" || die "unable to create working directories"
dd if="$block" of="$WORK/init_boot.img" bs=1048576 2>/dev/null || die "unable to read init_boot"
[ -s "$WORK/init_boot.img" ] || die "init_boot image is empty"

cd "$WORK/patch" || die "unable to enter patch directory"
"$MAGISKBOOT" unpack -h "$WORK/init_boot.img" >/dev/null 2>&1 || die "unable to unpack init_boot"
[ -f ramdisk.cpio ] || die "init_boot ramdisk missing"

marker_directory_exists=0
if "$MAGISKBOOT" cpio ramdisk.cpio "exists serial_lock" >/dev/null 2>&1; then
  marker_directory_exists=1
fi

if [ "$state" = verified ]; then
  # A matching serial never creates a marker. If an old marker directory is
  # present, remove the directory recursively; otherwise leave init_boot
  # byte-for-byte untouched.
  if [ "$marker_directory_exists" = 0 ]; then
    finished=1
    exit 0
  fi
  "$MAGISKBOOT" cpio ramdisk.cpio \
    "rm -r serial_lock" >/dev/null 2>&1 || die "unable to remove marker directory"
else
  # Only a mismatching serial may create the marker directory and marker.
  token=${SERIAL_LOCK_TOKEN:-}
  case "$token" in
    *[!0-9a-f]*|'') die "invalid build token" ;;
  esac
  [ ${#token} -eq 64 ] || die "invalid build token length"
  printf '%s\n' "$token" > marker.token || die "unable to create marker token"
  if [ "$marker_directory_exists" = 1 ]; then
    "$MAGISKBOOT" cpio ramdisk.cpio \
      "rm -r serial_lock" >/dev/null 2>&1 || die "unable to replace old marker directory"
  fi
  "$MAGISKBOOT" cpio ramdisk.cpio \
    "mkdir 0750 serial_lock" \
    "add 0400 serial_lock/.mismatch marker.token" >/dev/null 2>&1 \
    || die "unable to create mismatch marker"
fi

"$MAGISKBOOT" repack "$WORK/init_boot.img" "$WORK/init_boot-new.img" >/dev/null 2>&1 \
  || die "unable to repack init_boot"
[ -s "$WORK/init_boot-new.img" ] || die "repacked init_boot is empty"

cd "$WORK/verify" || die "unable to enter verification directory"
"$MAGISKBOOT" unpack -h "$WORK/init_boot-new.img" >/dev/null 2>&1 \
  || die "unable to unpack repacked init_boot"
if [ "$state" = verified ]; then
  if "$MAGISKBOOT" cpio ramdisk.cpio "exists serial_lock" >/dev/null 2>&1; then
    die "marker directory removal verification failed"
  fi
else
  rm -f marker.out
  "$MAGISKBOOT" cpio ramdisk.cpio \
    "extract serial_lock/.mismatch marker.out" >/dev/null 2>&1 \
    || die "marker extraction verification failed"
  [ "$(tr -d '\r\n' < marker.out 2>/dev/null)" = "$token" ] \
    || die "marker replacement verification failed"
fi

part_size=$(blockdev --getsize64 "$block" 2>/dev/null)
new_size=$(wc -c < "$WORK/init_boot-new.img" 2>/dev/null)
case "$part_size:$new_size" in
  *[!0-9:]*|:*|*:) die "partition size unavailable" ;;
esac
[ "$new_size" -le "$part_size" ] || die "repacked init_boot is oversized"

dd if="$WORK/init_boot-new.img" of="$block" bs=1048576 conv=fsync 2>/dev/null \
  || die "unable to write init_boot"
sync
dd if="$block" of="$WORK/readback.img" bs="$new_size" count=1 2>/dev/null \
  || die "unable to read back init_boot"
[ "$(sha256sum "$WORK/init_boot-new.img" | awk '{print $1}')" = \
  "$(sha256sum "$WORK/readback.img" | awk '{print $1}')" ] \
  || die "partition readback verification failed"

if [ "$state" = verified ]; then
  echo "existing marker directory removed from init_boot$slot"
else
  echo "current marker committed to init_boot$slot"
fi
finished=1
exit 0
