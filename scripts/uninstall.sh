#!/bin/bash
set -euo pipefail

LABEL="com.i5dr0id.ntfsremount"
APP_DST="/Applications/NTFSRemount.app"
PLIST_DST="/Library/LaunchDaemons/${LABEL}.plist"

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use: sudo make uninstall)" >&2
    exit 1
fi

echo "==> unloading daemon"
launchctl bootout "system/${LABEL}" 2>/dev/null || launchctl unload "${PLIST_DST}" 2>/dev/null || true

echo "==> removing files"
rm -f "${PLIST_DST}"
rm -rf "${APP_DST}"

echo "==> done"
echo "(You may also remove NTFSRemount from Full Disk Access in System Settings.)"
