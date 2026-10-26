#!/usr/bin/env bash
# Builds a release bundle and installs or updates /Applications/Olek.app.
# Tracking data lives in ~/Library/Application Support/Olek and is not touched.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$(scripts/bundle.sh release | tail -n 1)"
TARGET="/Applications/Olek.app"

if pgrep -f "$TARGET/Contents/MacOS/Olek" >/dev/null; then
    echo "Quitting running Olek..."
    pkill -f "$TARGET/Contents/MacOS/Olek" || true
    for _ in {1..20}; do
        pgrep -f "$TARGET/Contents/MacOS/Olek" >/dev/null || break
        sleep 0.25
    done
fi

rm -rf "$TARGET"
ditto "$APP" "$TARGET"
open "$TARGET"
echo "Installed $(defaults read "$TARGET/Contents/Info" CFBundleShortVersionString) to $TARGET"
