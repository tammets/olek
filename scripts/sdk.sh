# Sourced by the build and test scripts; picks a macOS SDK that Command Line Tools can compile against.
#
# From the macOS 27 SDK on, SwiftUI's @State is a macro expanded by the SwiftUIMacros compiler
# plugin, which ships with Xcode but not with Command Line Tools 27.0. Without it every view with
# @State fails to build. This falls back to the newest installed SDK whose SwiftUI does not need the
# plugin. It does nothing when SDKROOT is already set, with full Xcode, or once the plugin is installed.

olek_sdk_needs_swiftui_macros() {
    grep -qs 'module: "SwiftUIMacros", type: "StateMacro"' \
        "$1"/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/*-apple-macos.swiftinterface
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

olek_pick_sdk
