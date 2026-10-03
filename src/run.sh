#!/bin/bash
# Bluetooth audio keepalive: a minimal Chromium-based browser window holding
# the default output device open via a looping near-silent <audio> element.
# Isolated profile, so it is independent of normal browsing.
#
# Supervisor loop: the browser's auto-updater kills running instances, so
# relaunch in-process rather than relying solely on launchd's KeepAlive.

DIR="/Users/Shared/btkeepalive"
PROFILE="$DIR/profile"
PREFS="$PROFILE/Default/Preferences"

# Edge first, then Chrome. Either works — the mechanism is Chromium's media
# pipeline, not anything specific to one browser.
for candidate in \
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium"
do
  if [ -x "$candidate" ]; then BROWSER="$candidate"; break; fi
done

if [ -z "$BROWSER" ]; then
  echo "No Chromium-based browser found (Edge, Chrome, Brave, Chromium)." >&2
  exit 1
fi

# An unclean shutdown (battery cutoff, force quit) leaves exit_type=Crashed,
# which makes the browser come back on a restore prompt instead of the
# keepalive page — every process running, no audio playing. Clear it first.
clear_crash_flag() {
  [ -f "$PREFS" ] || return 0
  python3 - "$PREFS" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        d = json.load(f)
    d.setdefault('profile', {})['exit_type'] = 'Normal'
    d['profile']['exited_cleanly'] = True
    with open(path, 'w') as f:
        json.dump(d, f)
except Exception:
    pass
PY
}

# Sleep control: a continuous A2DP stream competes for the 2.4 GHz radio with
# Bluetooth mice and keyboards, so only play while the app that needs the
# speaker is in front, plus a grace period after it loses focus. The page
# polls state.js and pauses or resumes its <audio> element accordingly.
FOCUS_APP="com.anthropic.claudefordesktop"
GRACE=300
STATE="$DIR/state.js"

focus_loop() {
  local current="" want last_front=$SECONDS
  while true; do
    if lsappinfo info -only bundleid "$(lsappinfo front)" 2>/dev/null \
        | grep -q "\"$FOCUS_APP\""; then
      last_front=$SECONDS
    fi
    if [ $((SECONDS - last_front)) -lt "$GRACE" ]; then want=true; else want=false; fi
    if [ "$want" != "$current" ]; then
      echo "window.KEEPALIVE_ON = $want;" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
      current=$want
    fi
    sleep 2
  done
}

focus_loop &
FOCUS_PID=$!
echo "$FOCUS_PID" > "$DIR/focus.pid"
trap 'kill "$FOCUS_PID" 2>/dev/null' EXIT

while true; do
  clear_crash_flag
  "$BROWSER" \
    --app="file://$DIR/silence.html" \
    --user-data-dir="$PROFILE" \
    --autoplay-policy=no-user-gesture-required \
    --disable-features=CalculateNativeWinOcclusion \
    --disable-session-crashed-bubble \
    --hide-crash-restore-bubble \
    --no-first-run \
    --no-default-browser-check \
    --disable-background-timer-throttling \
    --disable-renderer-backgrounding \
    --disable-sync \
    --window-size=340,120 \
    --window-position=40,40
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] browser exited, relaunching in 10s" >&2
  sleep 10
done
