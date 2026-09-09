#!/system/bin/sh

STATE=/proc/oplus_serial_lock
BASE=/data/adb/serial_lock_stage
TOKEN_FILE=$BASE/build-token
MAGISKBOOT=$BASE/magiskboot
HOOK=/data/adb/service.d/service_log.sh
LOCK=$BASE/lock
WORK=$BASE/work.$$
LOG=$BASE/stage.log

mkdir -p "$BASE"
chmod 0700 "$BASE" 2>/dev/null
exec >>"$LOG" 2>&1

cleanup() {
  rm -rf "$WORK"
  rmdir "$LOCK" 2>/dev/null
  rm -f "$HOOK"
}
trap cleanup EXIT INT TERM

state=$(cat "$STATE" 2>/dev/null) || exit 0
if [ "$state" != mismatch-pending ]; then
  exit 0
fi
token=$(tr -d '\r\n' < "$TOKEN_FILE" 2>/dev/null)
case "$token" in
  *[!0-9a-f]*|'') echo "invalid build token"; exit 0 ;;
esac
[ ${#token} -eq 64 ] || { echo "invalid build token length"; exit 0; }
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
"$MAGISKBOOT" unpack -h ../init_boot.img >/dev/null 2>&1 || exit 0
[ -f ramdisk.cpio ] || { echo "init_boot ramdisk missing"; exit 0; }
printf '%s\n' "$token" > marker.token || exit 0
"$MAGISKBOOT" cpio ramdisk.cpio \
  "rm serial_lock/.mismatch" \
  "mkdir 0750 serial_lock" \
  "add 0400 serial_lock/.mismatch marker.token" >/dev/null 2>&1 || exit 0
"$MAGISKBOOT" repack ../init_boot.img ../init_boot-new.img >/dev/null 2>&1 || exit 0
[ -s ../init_boot-new.img ] || exit 0

cd "$WORK/verify" || exit 0
"$MAGISKBOOT" unpack -h ../init_boot-new.img >/dev/null 2>&1 || exit 0
"$MAGISKBOOT" cpio ramdisk.cpio "extract serial_lock/.mismatch marker.out" >/dev/null 2>&1 || exit 0
[ "$(tr -d '\r\n' < marker.out 2>/dev/null)" = "$token" ] || { echo "marker pre-flash verification failed"; exit 0; }

part_size=$(blockdev --getsize64 "$block" 2>/dev/null)
new_size=$(wc -c < "$WORK/init_boot-new.img" 2>/dev/null)
case "$part_size:$new_size" in *[!0-9:]*|:*|*:) echo "partition size unavailable"; exit 0 ;; esac
[ "$new_size" -le "$part_size" ] || { echo "repacked init_boot is oversized"; exit 0; }

backup=$BASE/init_boot${slot}_backup.img
if [ ! -s "$backup" ]; then
  cp "$WORK/init_boot.img" "$backup" || exit 0
  chmod 0600 "$backup" 2>/dev/null
fi
dd if="$WORK/init_boot-new.img" of="$block" bs=1048576 conv=fsync 2>/dev/null || exit 0
sync
dd if="$block" of="$WORK/readback.img" bs="$new_size" count=1 2>/dev/null || exit 0
[ "$(sha256sum "$WORK/init_boot-new.img" | awk '{print $1}')" = "$(sha256sum "$WORK/readback.img" | awk '{print $1}')" ] || { echo "partition readback verification failed"; exit 0; }

printf 'arm:%s\n' "$token" > "$STATE" 2>/dev/null || { echo "kernel refused arm command"; exit 0; }
[ "$(cat "$STATE" 2>/dev/null)" = mismatch-armed ] || { echo "kernel arm state verification failed"; exit 0; }
echo "marker committed to init_boot$slot; delayed reboot armed"
exit 0
