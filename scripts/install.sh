#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.i5dr0id.ntfsremount"
APP_SRC="${ROOT_DIR}/build/NTFSRemount.app"
APP_DST="/Applications/NTFSRemount.app"
PLIST_SRC="${ROOT_DIR}/Resources/${LABEL}.plist"
PLIST_DST="/Library/LaunchDaemons/${LABEL}.plist"

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use: sudo make install)" >&2
    exit 1
fi

if [ ! -d "${APP_SRC}" ]; then
    echo "App bundle not found at ${APP_SRC}. Run 'make build' first." >&2
    exit 1
fi

echo "==> installing ${APP_DST}"
rm -rf "${APP_DST}"
cp -R "${APP_SRC}" "${APP_DST}"
chown -R root:wheel "${APP_DST}"

echo "==> installing ${PLIST_DST}"
install -m 644 -o root -g wheel "${PLIST_SRC}" "${PLIST_DST}"

echo "==> loading daemon"
launchctl bootout "system/${LABEL}" 2>/dev/null || true
launchctl bootstrap system "${PLIST_DST}"
launchctl enable "system/${LABEL}" 2>/dev/null || true

echo "==> done. logs: /var/log/ntfsremount.log"
echo
echo "NEXT STEP: grant Full Disk Access to NTFSRemount."
echo "  System Settings > Privacy & Security > Full Disk Access"
echo "  Add /Applications/NTFSRemount.app and turn it ON, then replug the drive."
