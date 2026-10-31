#!/usr/bin/env bash
# Runs the test suite. With only Command Line Tools installed, Swift Testing lives outside
# the default search paths, so they are added here. With full Xcode this is a plain `swift test`.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh

DEV="$(xcode-select -p)/Library/Developer"
if [[ -d "$DEV/Frameworks/Testing.framework" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
    # The macro plugin is named explicitly: when the app target rebuilds in the same run, the
    # module scanner can otherwise leave it out and every @Test fails to expand.
    exec swift test \
        -Xswiftc -F -Xswiftc "$DEV/Frameworks" \
        -Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing" \
        -Xlinker -F -Xlinker "$DEV/Frameworks" \
        -Xlinker -rpath -Xlinker "$DEV/Frameworks" \
        -Xlinker -rpath -Xlinker "$DEV/usr/lib" \
        $OLEK_LINK_FLAGS "$@"
fi
exec swift test $OLEK_LINK_FLAGS "$@"
