# Sourced by the build and test scripts; picks a macOS SDK that Command Line Tools can compile against.
#
# From the macOS 27 SDK on, SwiftUI's @State is a macro expanded by the SwiftUIMacros compiler
# plugin, which ships with Xcode but not with Command Line Tools 27.0. Without it every view with
# @State fails to build. This falls back to the newest installed SDK whose SwiftUI does not need the
# plugin. The choice is skipped when SDKROOT is already set, with full Xcode, or once the plugin is installed.

olek_sdk_needs_swiftui_macros() {
    grep -qs 'module: "SwiftUIMacros", type: "StateMacro"' \
        "$1"/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/*-apple-macos.swiftinterface
}

# Extra `swift build` and `swift test` arguments whenever SDKROOT is set; empty otherwise.
OLEK_LINK_FLAGS=""

# The deployment target from Package.swift, e.g. ".macOS(.v14)" -> "14.0".
olek_min_macos() {
    local v
    v="$(sed -nE 's/.*\.macOS\(\.v([0-9]+)(_([0-9]+))?\).*/\1.\3/p' Package.swift | head -n 1)"
    [[ "$v" == *. ]] && v="${v}0"
    echo "$v"
}

olek_pick_sdk() {
    local dev plugins sdk
    dev="$(xcode-select -p)"
    [[ -z "${SDKROOT:-}" && "$dev" == *CommandLineTools* ]] || return 0
    plugins="$dev/usr/lib/swift/host/plugins"
    compgen -G "$plugins/libSwiftUIMacros.*" > /dev/null && return 0
    olek_sdk_needs_swiftui_macros "$(xcrun --show-sdk-path)" || return 0

    # Real SDK folders only; MacOSX.sdk and MacOSX26.sdk are symlinks to them.
    for sdk in $(find "$dev/SDKs" -maxdepth 1 -name 'MacOSX[0-9]*.sdk' -type d | sort -rV); do
        if ! olek_sdk_needs_swiftui_macros "$sdk"; then
            echo "note: the default SDK needs the SwiftUIMacros plugin, which Command Line Tools lack; building with $(basename "$sdk")" >&2
            export SDKROOT="$sdk"
            return 0
        fi
    done
    echo "warning: no installed SDK builds SwiftUI without the SwiftUIMacros plugin; install Xcode or a newer Command Line Tools" >&2
}

# SwiftPM does not pass an SDK given through SDKROOT on to the linker, which then records the
# deployment target as the SDK version. macOS draws apps built for an SDK before 26 in the old
# style: flat grey popover, small corners, no Liquid Glass. So the version is passed explicitly.
olek_link_flags() {
    [[ -n "${SDKROOT:-}" ]] || return 0
    local min sdk_version
    min="$(olek_min_macos)"
    sdk_version="$(plutil -extract Version raw -o - "$SDKROOT/SDKSettings.json" 2>/dev/null || true)"
    if [[ -z "$min" || -z "$sdk_version" ]]; then
        echo "warning: could not read the deployment target or the version of $SDKROOT; the app may get the old look" >&2
        return 0
    fi
    OLEK_LINK_FLAGS="-Xlinker -platform_version -Xlinker macos -Xlinker $min -Xlinker $sdk_version"
}

olek_pick_sdk
olek_link_flags
