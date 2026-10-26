#!/usr/bin/env bash
# Builds a release bundle and zips it into dist/ for sharing, e.g. as a GitHub release asset.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$(scripts/bundle.sh release | tail -n 1)"
VERSION="$(tr -d '[:space:]' < VERSION)"
mkdir -p dist
ZIP="dist/Olek-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "$PWD/$ZIP"
