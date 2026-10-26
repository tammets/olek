#!/usr/bin/env bash
# Development loop: build the debug bundle, stop any running dev instance, launch it.
# The installed release app in /Applications is left alone.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$(scripts/bundle.sh debug | tail -n 1)"
pkill -f "Olek Dev.app/Contents/MacOS/Olek" 2>/dev/null && sleep 0.5 || true
open "$APP"
echo "Launched $APP"
