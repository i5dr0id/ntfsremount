#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.i5dr0id.ntfsremount"
BINARY_SRC="${ROOT_DIR}/build/ntfsremount"
BINARY_DST="/usr/local/sbin/ntfsremount"
PLIST_SRC="${ROOT_DIR}/Resources/${LABEL}.plist"
PLIST_DST="/Library/LaunchDaemons/${LABEL}.plist"

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use: sudo make install)" >&2
    exit 1
fi

if [ ! -x "${BINARY_SRC}" ]; then
    echo "Binary not found at ${BINARY_SRC}. Run 'make build' first." >&2
    exit 1
fi

echo "==> installing ${BINARY_DST}"
install -d -m 755 /usr/local/sbin
install -m 755 "${BINARY_SRC}" "${BINARY_DST}"

echo "==> installing ${PLIST_DST}"
install -m 644 -o root -g wheel "${PLIST_SRC}" "${PLIST_DST}"

echo "==> loading daemon"
launchctl bootout "system/${LABEL}" 2>/dev/null || true
launchctl bootstrap system "${PLIST_DST}"
launchctl enable "system/${LABEL}" 2>/dev/null || true

echo "==> done. logs: /var/log/ntfsremount.log"
