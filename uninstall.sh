#!/bin/bash
# Removes the Bluetooth audio keepalive completely.

DIR="/Users/Shared/btkeepalive"
AGENTS="$HOME/Library/LaunchAgents"
LABEL="com.local.btkeepalive"
WATCHDOG="com.local.btkeepalive.watchdog"

echo "Removing Bluetooth audio keepalive"
echo

# Watchdog first, or it will restart the keepalive mid-uninstall.
launchctl bootout "gui/$UID/$WATCHDOG" 2>/dev/null && echo "  watchdog stopped"
launchctl bootout "gui/$UID/$LABEL"    2>/dev/null && echo "  keepalive stopped"
pkill -f 'btkeepalive/profile' 2>/dev/null && echo "  browser window closed"
sleep 2

rm -f "$AGENTS/$LABEL.plist" "$AGENTS/$WATCHDOG.plist" && echo "  agents removed"
rm -f "$HOME/Desktop/Restart BT Keepalive.command" \
      "$HOME/Desktop/Stop BT Keepalive.command" && echo "  shortcuts removed"
rm -rf "$DIR" && echo "  files removed ($DIR)"

echo
echo "Done. Bluetooth speaker audio will revert to its previous behaviour."
