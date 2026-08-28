#!/bin/bash
# Double-click to fully stop the Bluetooth audio keepalive.
#
# Stops the watchdog FIRST: otherwise it would notice the keepalive missing
# and restart it within two minutes.

EDGE="com.local.btkeepalive"
WATCHDOG="com.local.btkeepalive.watchdog"

echo "Stopping Bluetooth keepalive..."
echo

echo "  1. stopping watchdog"
launchctl bootout "gui/$UID/$WATCHDOG" 2>/dev/null

echo "  2. stopping keepalive agent"
launchctl bootout "gui/$UID/$EDGE" 2>/dev/null

echo "  3. closing browser keepalive window"
pkill -f 'btkeepalive/profile' 2>/dev/null

sleep 4

# Verify nothing came back.
snapshot=$(ps axo args 2>/dev/null)
remaining=$(printf '%s\n' "$snapshot" | grep -c 'btkeepalive/profile')
loaded=$(launchctl list | grep -c btkeepalive)

echo
if [ "$remaining" -eq 0 ] && [ "$loaded" -eq 0 ]; then
    echo "STOPPED - nothing running, nothing scheduled."
    echo
    echo "Bluetooth speaker audio will stop working until you"
    echo "run 'Restart BT Keepalive' from the Desktop."
else
    echo "WARNING - something is still active:"
    echo "  Browser processes still running: $remaining"
    echo "  launchd agents still loaded:  $loaded"
    launchctl list | grep btkeepalive
fi

echo
read -n 1 -s -r -p "Press any key to close..."
echo
