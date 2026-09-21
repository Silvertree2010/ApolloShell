#!/bin/sh
# Run the tests. Without Xcode, Swift Testing ships in the Command Line Tools
# but is not on SwiftPM's search path, so the paths are passed by hand
# (same fix as ApolloShell's test.sh).
set -eu
cd "$(dirname "$0")"

CLT=/Library/Developer/CommandLineTools
FW=$CLT/Library/Developer/Frameworks
LIB=$CLT/Library/Developer/usr/lib

swift test \
    -Xswiftc -F"$FW" \
    -Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing" \
    -Xlinker -F"$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
