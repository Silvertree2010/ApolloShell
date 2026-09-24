#!/bin/sh
set -eu
cd "$(dirname "$0")"

CLT=/Library/Developer/CommandLineTools
FW=$CLT/Library/Developer/Frameworks
LIB=$CLT/Library/Developer/usr/lib

export SDKROOT="$CLT/SDKs/MacOSX26.sdk"

swift test \
    -Xswiftc -F"$FW" \
    -Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing" \
    -Xlinker -F"$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
