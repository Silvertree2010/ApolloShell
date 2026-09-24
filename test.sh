#!/bin/sh
# Tests ausfuehren. Ohne Xcode liegt Swift Testing zwar in den Command Line
# Tools, aber nicht im Suchpfad von SwiftPM - deshalb die Pfade von Hand.
set -eu
cd "$(dirname "$0")"

CLT=/Library/Developer/CommandLineTools
FW=$CLT/Library/Developer/Frameworks
LIB=$CLT/Library/Developer/usr/lib

# SDK fest auf macOS 26: Die Command Line Tools 26.6 (14.09.2026) bringen
# Compiler Swift 6.3.3, stellen aber das mitgelieferte macOS-27-SDK (Swift
# 6.4) als Standard ein - damit liest der Compiler SwiftUI falsch.
export SDKROOT="$CLT/SDKs/MacOSX26.sdk"

# Das Makro-Plugin von Swift Testing liegt dort ebenfalls nicht im Suchpfad.
swift test \
    -Xswiftc -F"$FW" \
    -Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing" \
    -Xlinker -F"$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
