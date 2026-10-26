#!/usr/bin/env bash
# Runs the test suite. With only Command Line Tools installed, Swift Testing lives outside
# the default search paths, so they are added here. With full Xcode this is a plain `swift test`.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV="$(xcode-select -p)/Library/Developer"
if [[ -d "$DEV/Frameworks/Testing.framework" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
    exec swift test \
        -Xswiftc -F -Xswiftc "$DEV/Frameworks" \
        -Xlinker -F -Xlinker "$DEV/Frameworks" \
        -Xlinker -rpath -Xlinker "$DEV/Frameworks" \
        -Xlinker -rpath -Xlinker "$DEV/usr/lib" \
        "$@"
fi
exec swift test "$@"
