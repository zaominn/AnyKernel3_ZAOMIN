#!/sbin/sh

serial_lock_prepare() {
  local token base hook
  token=$(tr -d '\r\n' < "$AKHOME/serial_lock/build-token" 2>/dev/null)
  case "$token" in *[!0-9a-f]*|'') ui_print "- Invalid serial lock build token"; return 1 ;; esac
  [ ${#token} -eq 64 ] || { ui_print "- Invalid serial lock token length"; return 1; }
  [ -x "$AKHOME/tools/magiskboot" ] || { ui_print "- magiskboot is unavailable"; return 1; }
  [ -d /data/adb ] && [ -w /data/adb ] || { ui_print "- /data/adb is unavailable; refusing an unsafe serial-locked flash"; return 1; }

  # AK3 only deploys the one-shot service. It never reads, creates, removes,
  # or rewrites the init_boot marker itself.
  base=/data/local/tmp/serial_lock_stage
  hook=/data/adb/service.d/service_log.sh
  rm -rf /data/adb/modules/oplus-serial-lock-stage
  rm -f /data/adb/post-fs-data.d/00-oplus-serial-lock-stage.sh
  rm -rf "$base"
  mkdir -p "$base" /data/adb/service.d || return 1
  cp "$AKHOME/serial_lock/post-fs-data.sh" "$base/stage.sh" || return 1
  cp "$AKHOME/serial_lock/build-token" "$base/build-token" || return 1
  cp "$AKHOME/tools/magiskboot" "$base/magiskboot" || return 1
  printf '%s\n' '#!/system/bin/sh' \
    'exec /system/bin/sh /data/local/tmp/serial_lock_stage/stage.sh' > "$hook" || return 1
  chmod 0700 "$base" || return 1
  chmod 0755 "$base/stage.sh" "$base/magiskboot" "$hook" || return 1
  chmod 0600 "$base/build-token" || return 1
  return 0
}
