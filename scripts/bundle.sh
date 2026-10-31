#!/usr/bin/env bash
# Builds Olek and assembles a signed .app bundle in build/.
#
#   scripts/bundle.sh          debug build  -> build/Olek Dev.app  (ee.olek.app.dev, separate data)
#   scripts/bundle.sh release  release build -> build/Olek.app     (ee.olek.app)
#
# Prints the bundle path on the last line of output.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
case "$CONFIG" in
    debug)   APP_NAME="Olek Dev"; BUNDLE_ID="ee.olek.app.dev" ;;
    release) APP_NAME="Olek";     BUNDLE_ID="ee.olek.app" ;;
    *) echo "usage: $0 [debug|release]" >&2; exit 1 ;;
esac

source scripts/sdk.sh

# Unquoted on purpose: the flags are separate words without spaces.
swift build -c "$CONFIG" $OLEK_LINK_FLAGS >&2
BIN_DIR="$(swift build -c "$CONFIG" $OLEK_LINK_FLAGS --show-bin-path)"

# macOS draws apps built for an SDK before 26 in the old style, so a release must not slip back.
SDK_VERSION="$(vtool -show-build "$BIN_DIR/Olek" | awk '$1 == "sdk" { print $2; exit }')"
if [[ "$CONFIG" == release && "${SDK_VERSION%%.*}" -lt 26 ]]; then
    echo "error: the binary was built for macOS SDK $SDK_VERSION; releases need SDK 26 or later" >&2
    exit 1
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Olek" "$APP/Contents/MacOS/Olek"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" \
    -e "s/__APP_NAME__/$APP_NAME/" \
    -e "s/__VERSION__/$VERSION/" \
    -e "s/__BUILD__/$BUILD/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >&2

# Ad-hoc signature: no Apple Developer account needed. Binds Info.plist to the binary
# so macOS sees a consistent bundle identity for notifications and login items.
codesign --force --sign - --timestamp=none "$APP" >&2

echo "$PWD/$APP"
