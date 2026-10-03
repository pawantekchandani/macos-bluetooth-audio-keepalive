#!/bin/bash
# Verifies the Bluetooth keepalive is genuinely working and repairs it if not.
#
# Checks two things, because each has failed in practice:
#   1. the launchd service still exists in the user domain (it has been
#      evicted more than once, e.g. around a browser auto-update)
#   2. the browser is actually playing audio, not merely running — after an
#      unclean shutdown it can sit on a crash-restore page with no playback
#
# The playback test is the presence of Chromium's audio service subprocess,
# which is spawned only while audio is in use. A CoreAudio device-is-running
# query was tried first and proved useless: the built-in output device reports
# "running" permanently, so it never detects a failure.

LABEL="com.local.btkeepalive"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DIR="/Users/Shared/btkeepalive"
LOG="$DIR/watchdog.log"

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

# Keep the log from growing without bound.
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 200000 ]; then
  tail -n 300 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

# Snapshot ps into a variable first: piping ps straight into grep lets the
# grep processes appear in ps's own output and match their own pattern, which
# would make this always return true and the watchdog never repair anything.
audio_active() {
  local snapshot
  snapshot=$(ps axo args 2>/dev/null)
  printf '%s\n' "$snapshot" \
    | grep 'btkeepalive/profile' \
    | grep -q 'audio.mojom.AudioService'
}

restart() {
  log "REPAIR: $1 — restarting keepalive"
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null
  pkill -f 'btkeepalive/profile' 2>/dev/null
  sleep 3
  if launchctl bootstrap "gui/$UID" "$PLIST" 2>>"$LOG"; then
    sleep 12
    if audio_active; then
      log "REPAIR: ok, audio service running"
    else
      log "REPAIR: bootstrapped but audio service still absent"
    fi
  else
    log "REPAIR: bootstrap FAILED"
  fi
}

# 1. Service present?
if ! launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
  restart "service missing from launchd domain"
  exit 0
fi

# 2. Asleep on purpose? The keepalive pauses while the app that needs the
#    speaker is out of focus (see run.sh), so no audio is expected — but only
#    if the loop that would wake it again is still alive.
if grep -q 'false' "$DIR/state.js" 2>/dev/null; then
  if ! kill -0 "$(cat "$DIR/focus.pid" 2>/dev/null)" 2>/dev/null; then
    restart "asleep but sleep-control loop is dead"
  fi
  exit 0
fi

# 3. Audio actually playing? Re-check before acting, so a brief gap during an
#    output-device switch does not trigger a needless restart.
if ! audio_active; then
  sleep 10
  if ! audio_active; then
    restart "browser running but no audio service (playback stopped)"
    exit 0
  fi
fi

exit 0
