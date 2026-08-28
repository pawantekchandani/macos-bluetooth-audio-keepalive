#!/bin/bash
# Double-click to restart the Bluetooth audio keepalive.

LABEL="com.local.btkeepalive"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
WATCHDOG="com.local.btkeepalive.watchdog"
WATCHDOG_PLIST="$HOME/Library/LaunchAgents/$WATCHDOG.plist"

# Snapshot ps first so the grep processes cannot match their own pattern.
audio_active() {
    local snapshot
    snapshot=$(ps axo args 2>/dev/null)
    printf '%s\n' "$snapshot" \
      | grep 'btkeepalive/profile' \
      | grep -q 'audio.mojom.AudioService'
}

echo "Restarting Bluetooth keepalive..."
echo

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null
pkill -f 'btkeepalive/profile' 2>/dev/null
sleep 3

if ! launchctl bootstrap "gui/$UID" "$PLIST" 2>&1; then
    echo "Could not start the agent."
    echo "Check that this file exists:"
    echo "  $PLIST"
    echo
    read -n 1 -s -r -p "Press any key to close..."
    exit 1
fi

# The stop shortcut unloads the watchdog too, so bring it back.
if ! launchctl print "gui/$UID/$WATCHDOG" >/dev/null 2>&1; then
    launchctl bootstrap "gui/$UID" "$WATCHDOG_PLIST" 2>/dev/null \
        && echo "Watchdog restarted." \
        || echo "Note: watchdog could not be started."
fi

echo "Agent started. Waiting for audio..."
sleep 12

n=$(pgrep -f 'btkeepalive/profile' | wc -l | tr -d ' ')
echo "Browser processes: $n"

if audio_active; then
    echo
    echo "OK - audio is playing. Bluetooth speaker output should work now."
else
    echo
    echo "WARNING - the browser is running but not playing audio."
    echo "Look at the 'BT keepalive' window: it should say PLAYING"
    echo "with the t= value counting up."
fi

echo
read -n 1 -s -r -p "Press any key to close..."
echo
