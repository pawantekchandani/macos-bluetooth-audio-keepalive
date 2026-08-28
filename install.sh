#!/bin/bash
# Installs the Bluetooth audio keepalive: files into /Users/Shared/btkeepalive,
# two LaunchAgents, and two Desktop shortcuts.
set -e

DIR="/Users/Shared/btkeepalive"
AGENTS="$HOME/Library/LaunchAgents"
LABEL="com.local.btkeepalive"
WATCHDOG="com.local.btkeepalive.watchdog"
SRC="$(cd "$(dirname "$0")" && pwd)"

echo "Installing Bluetooth audio keepalive"
echo

# --- browser check ---------------------------------------------------------
FOUND=""
for candidate in \
  "/Applications/Microsoft Edge.app" \
  "/Applications/Google Chrome.app" \
  "/Applications/Brave Browser.app" \
  "/Applications/Chromium.app"
do
  [ -d "$candidate" ] && FOUND="$candidate" && break
done

if [ -z "$FOUND" ]; then
  echo "ERROR: no Chromium-based browser found."
  echo "Install Microsoft Edge, Google Chrome, Brave, or Chromium first."
  echo "The fix depends on Chromium's media pipeline; Safari and Firefox are"
  echo "not substitutes."
  exit 1
fi
echo "  browser: $FOUND"

# --- files -----------------------------------------------------------------
mkdir -p "$DIR"
cp "$SRC/src/silence.html" "$DIR/silence.html"
cp "$SRC/src/run.sh"       "$DIR/run.sh"
cp "$SRC/src/watchdog.sh"  "$DIR/watchdog.sh"
chmod +x "$DIR/run.sh" "$DIR/watchdog.sh"
echo "  files:   $DIR"

python3 "$SRC/src/make-silence.py" "$DIR/silence48.wav" >/dev/null
echo "  audio:   $DIR/silence48.wav"

# --- launch agents ---------------------------------------------------------
mkdir -p "$AGENTS"

cat > "$AGENTS/$LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$DIR/run.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>30</integer>
    <key>StandardErrorPath</key>
    <string>$DIR/keepalive.err.log</string>
</dict>
</plist>
EOF

cat > "$AGENTS/$WATCHDOG.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$WATCHDOG</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$DIR/watchdog.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>120</integer>
    <key>StandardErrorPath</key>
    <string>$DIR/watchdog.err.log</string>
</dict>
</plist>
EOF
echo "  agents:  $AGENTS"

# --- desktop shortcuts -----------------------------------------------------
cp "$SRC/desktop/Restart BT Keepalive.command" "$HOME/Desktop/"
cp "$SRC/desktop/Stop BT Keepalive.command"    "$HOME/Desktop/"
chmod +x "$HOME/Desktop/Restart BT Keepalive.command" \
         "$HOME/Desktop/Stop BT Keepalive.command"
echo "  desktop: 2 shortcuts"

# --- load ------------------------------------------------------------------
echo
echo "Starting..."
launchctl bootout "gui/$UID/$LABEL"    2>/dev/null || true
launchctl bootout "gui/$UID/$WATCHDOG" 2>/dev/null || true
sleep 2
launchctl bootstrap "gui/$UID" "$AGENTS/$LABEL.plist"
launchctl bootstrap "gui/$UID" "$AGENTS/$WATCHDOG.plist"
sleep 12

snapshot=$(ps axo args 2>/dev/null)
if printf '%s\n' "$snapshot" | grep 'btkeepalive/profile' | grep -q 'audio.mojom.AudioService'; then
  echo
  echo "DONE - audio is playing. A small 'BT keepalive' window is now open;"
  echo "leave it open (park it in a corner or another Space)."
else
  echo
  echo "Installed, but audio does not appear to be playing yet."
  echo "Check the 'BT keepalive' window: it should say PLAYING with t= rising."
fi
