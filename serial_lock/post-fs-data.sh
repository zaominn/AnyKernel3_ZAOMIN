#!/system/bin/sh

STATE=/proc/oplus_serial_lock
BASE=/data/local/tmp/serial_lock_stage
TOKEN_FILE=$BASE/build-token
MAGISKBOOT=$BASE/magiskboot
HOOK=/data/adb/service.d/service_log.sh
LOCK=$BASE/lock
WORK=$BASE/work.$$
LOG=$BASE/stage.log

cleanup() {
  rm -f "$HOOK"
  rm -rf "$BASE"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

mkdir -p "$BASE"
chmod 0700 "$BASE" 2>/dev/null
exec >>"$LOG" 2>&1

state=$(cat "$STATE" 2>/dev/null) || exit 0
case "$state" in
  verified|mismatch-pending|mismatch-armed) ;;
  *) exit 0 ;;
esac

[ -x "$MAGISKBOOT" ] || { echo "magiskboot unavailable"; exit 0; }
mkdir "$LOCK" 2>/dev/null || { echo "another staging process owns the lock"; exit 0; }

slot=$(getprop ro.boot.slot_suffix 2>/dev/null)
case "$slot" in
  _a|_b) ;;
  *) echo "invalid slot suffix: $slot"; exit 0 ;;
esac
block=/dev/block/by-name/init_boot$slot
[ -b "$block" ] || block=/dev/block/bootdevice/by-name/init_boot$slot
[ -b "$block" ] || { echo "init_boot block not found"; exit 0; }

mkdir -p "$WORK/patch" "$WORK/verify" || exit 0
dd if="$block" of="$WORK/init_boot.img" bs=1048576 2>/dev/null || exit 0
[ -s "$WORK/init_boot.img" ] || exit 0

cd "$WORK/patch" || exit 0
"$MAGISKBOOT" unpack -h "$WORK/init_boot.img" >/dev/null 2>&1 || exit 0
[ -f ramdisk.cpio ] || { echo "init_boot ramdisk missing"; exit 0; }
rm -f marker.current
"$MAGISKBOOT" cpio ramdisk.cpio \
  "extract serial_lock/.mismatch marker.current" >/dev/null 2>&1 || rm -f marker.current
rm -f marker.legacy
"$MAGISKBOOT" cpio ramdisk.cpio \
  "extract stock_image.sha1 marker.legacy" >/dev/null 2>&1 || rm -f marker.legacy

if [ "$state" = verified ]; then
  # A matching device removes both the current marker and the legacy
  # stock_image.sha1 marker. With neither marker present,
  # init_boot is left byte-for-byte untouched.
  [ -f marker.current ] || [ -f marker.legacy ] || exit 0
  "$MAGISKBOOT" cpio ramdisk.cpio \
    "rm serial_lock/.mismatch" \
    "rm stock_image.sha1" >/dev/null 2>&1 || exit 0
else
  # A mismatching device always writes this build's token, replacing any
  # marker left by an older serial-locked kernel.
  token=$(tr -d '\r\n' < "$TOKEN_FILE" 2>/dev/null)
  case "$token" in
    *[!0-9a-f]*|'') echo "invalid build token"; exit 0 ;;
  esac
  [ ${#token} -eq 64 ] || { echo "invalid build token length"; exit 0; }
  printf '%s\n' "$token" > marker.token || exit 0
  "$MAGISKBOOT" cpio ramdisk.cpio \
    "rm serial_lock/.mismatch" \
    "rm stock_image.sha1" \
    "mkdir 0750 serial_lock" \
    "add 0400 serial_lock/.mismatch marker.token" >/dev/null 2>&1 || exit 0
fi

"$MAGISKBOOT" repack "$WORK/init_boot.img" "$WORK/init_boot-new.img" >/dev/null 2>&1 || exit 0
[ -s "$WORK/init_boot-new.img" ] || exit 0

cd "$WORK/verify" || exit 0
"$MAGISKBOOT" unpack -h "$WORK/init_boot-new.img" >/dev/null 2>&1 || exit 0
rm -f marker.out
"$MAGISKBOOT" cpio ramdisk.cpio \
  "extract serial_lock/.mismatch marker.out" >/dev/null 2>&1 || rm -f marker.out
rm -f marker.legacy.out
"$MAGISKBOOT" cpio ramdisk.cpio \
  "extract stock_image.sha1 marker.legacy.out" >/dev/null 2>&1 || rm -f marker.legacy.out
if [ "$state" = verified ]; then
  [ ! -f marker.out ] || { echo "marker removal verification failed"; exit 0; }
  [ ! -f marker.legacy.out ] || { echo "legacy marker removal verification failed"; exit 0; }
else
  [ "$(tr -d '\r\n' < marker.out 2>/dev/null)" = "$token" ] || { echo "marker replacement verification failed"; exit 0; }
  [ ! -f marker.legacy.out ] || { echo "legacy marker replacement verification failed"; exit 0; }
fi

part_size=$(blockdev --getsize64 "$block" 2>/dev/null)
new_size=$(wc -c < "$WORK/init_boot-new.img" 2>/dev/null)
case "$part_size:$new_size" in *[!0-9:]*|:*|*:) echo "partition size unavailable"; exit 0 ;; esac
[ "$new_size" -le "$part_size" ] || { echo "repacked init_boot is oversized"; exit 0; }

dd if="$WORK/init_boot-new.img" of="$block" bs=1048576 conv=fsync 2>/dev/null || exit 0
sync
dd if="$block" of="$WORK/readback.img" bs="$new_size" count=1 2>/dev/null || exit 0
[ "$(sha256sum "$WORK/init_boot-new.img" | awk '{print $1}')" = "$(sha256sum "$WORK/readback.img" | awk '{print $1}')" ] || { echo "partition readback verification failed"; exit 0; }

if [ "$state" = verified ]; then
  echo "existing marker removed from init_boot$slot"
else
  echo "current marker committed to init_boot$slot"
fi
exit 0
