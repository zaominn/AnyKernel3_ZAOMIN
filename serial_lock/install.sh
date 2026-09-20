#!/sbin/sh

serial_lock_prepare() {
  local token hook hook_tmp helper
  token=$(tr -d '\r\n' < "$AKHOME/serial_lock/build-token" 2>/dev/null)
  case "$token" in *[!0-9a-f]*|'') ui_print "- Invalid serial lock build token"; return 1 ;; esac
  [ ${#token} -eq 64 ] || { ui_print "- Invalid serial lock token length"; return 1; }
  [ -x "$AKHOME/tools/magiskboot" ] || { ui_print "- magiskboot is unavailable"; return 1; }
  [ -x "$AKHOME/tools/busybox" ] || { ui_print "- busybox is unavailable"; return 1; }
  [ -d /data/adb ] && [ -w /data/adb ] || { ui_print "- /data/adb is unavailable; refusing an unsafe serial-locked flash"; return 1; }

  # The service creates its working directory in /tmp after Android starts.
  # Only the hook and a non-executable helper file need to cross the reboot.
  hook=/data/adb/service.d/service_log.sh
  hook_tmp=${hook}.tmp
  helper=/data/adb/.serial_lock_magiskboot
  rm -rf /data/adb/modules/oplus-serial-lock-stage
  rm -f /data/adb/post-fs-data.d/00-oplus-serial-lock-stage.sh
  rm -f "$hook" "$hook_tmp" "$helper"
  mkdir -p /data/adb/service.d || return 1
  cp "$AKHOME/tools/magiskboot" "$helper" || return 1
  chmod 0600 "$helper" || { rm -f "$helper"; return 1; }
  {
    printf '%s\n' '#!/system/bin/sh'
    printf "SERIAL_LOCK_TOKEN='%s'\n" "$token"
    printf "SERIAL_LOCK_MAGISKBOOT='%s'\n" "$helper"
    "$AKHOME/tools/busybox" sed '1d' "$AKHOME/serial_lock/post-fs-data.sh"
  } > "$hook_tmp" || { rm -f "$hook_tmp" "$helper"; return 1; }
  chmod 0755 "$hook_tmp" || { rm -f "$hook_tmp" "$helper"; return 1; }
  mv -f "$hook_tmp" "$hook" || { rm -f "$hook_tmp" "$helper"; return 1; }
  return 0
}
