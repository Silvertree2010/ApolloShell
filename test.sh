#!/bin/sh
# Run the tests. Without Xcode, Swift Testing does ship with the Command
# Line Tools, but not in SwiftPM's search path - hence the manual paths.
set -eu
cd "$(dirname "$0")"

CLT=/Library/Developer/CommandLineTools
FW=$CLT/Library/Developer/Frameworks
LIB=$CLT/Library/Developer/usr/lib

# SDK pinned to macOS 26: the Command Line Tools 26.6 (2026-09-14) ship
# compiler Swift 6.3.3, but make their bundled macOS 27 SDK (Swift 6.4) the
# default - with which the compiler reads SwiftUI wrong.
export SDKROOT="$CLT/SDKs/MacOSX26.sdk"

# Swift Testing's macro plugin is not in the search path there either.
swift test \
    -Xswiftc -F"$FW" \
    -Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing" \
    -Xlinker -F"$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
