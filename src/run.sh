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

# Prefer a browser that is not used for anything else. The keepalive is a
# normal running instance of whichever browser it picks: clicking that
# browser's Dock icon opens windows inside it, on this isolated profile, and
# they close whenever the keepalive restarts. Any Chromium browser works —
# the mechanism is Chromium's media pipeline.
for candidate in \
  "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium" \
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
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
# Bluetooth mice and keyboards, so only play while it is needed, plus a grace
# period afterwards. Needed means either the focus app is in front (so its
# audio starts with no gap) or any other process is asking for audio output
# (a browser tab reading aloud, for example). The page polls state.js and
# pauses or resumes its <audio> element accordingly.
FOCUS_APP="com.anthropic.claudefordesktop"
GRACE=300
STATE="$DIR/state.js"

# coreaudiod takes a power assertion on behalf of every process with an open
# output stream — including ones that are silent because the route is not yet
# open. Sets SELF (the keepalive's own browser) and OTHER (anything else).
audio_holders() {
  local pid
  SELF=0 OTHER=0
  for pid in $(pmset -g assertions | grep -A1 'coreaudiod' \
      | sed -n 's/.*Created for PID: \([0-9]*\).*/\1/p'); do
    if ps -o args= -p "$pid" 2>/dev/null | grep -q 'btkeepalive/profile'; then
      SELF=1
    else
      OTHER=1
    fi
  done
}

focus_loop() {
  local current="" want last_front=$SECONDS stalled=0
  while true; do
    audio_holders
    if [ "$OTHER" = 1 ] || lsappinfo info -only bundleid "$(lsappinfo front)" \
        2>/dev/null | grep -q "\"$FOCUS_APP\""; then
      last_front=$SECONDS
    fi
    if [ $((SECONDS - last_front)) -lt "$GRACE" ]; then want=true; else want=false; fi
    if [ "$want" != "$current" ]; then
      echo "window.KEEPALIVE_ON = $want;" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
      current=$want
    fi

    # Meant to be playing but the browser holds no output stream: the page has
    # stalled. It does this with every process still running and no error, so
    # nothing else notices. Kill it; the supervisor loop below relaunches it.
    if [ "$current" = true ] && [ "$SELF" = 0 ]; then
      stalled=$((stalled + 1))
      if [ "$stalled" -ge 15 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] playback stalled, restarting browser" >&2
        pkill -f 'btkeepalive/profile' 2>/dev/null
        stalled=-15   # allow time for the relaunch before checking again
      fi
    else
      stalled=0
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
    --disable-backgrounding-occluded-windows \
    --disable-sync \
    --window-size=340,120 \
    --window-position=40,40
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] browser exited, relaunching in 10s" >&2
  sleep 10
done
