#!/bin/sh
# Builds MediaRemoteAdapter.framework from extras/mediaremote-adapter -
# without cmake, with clang from the Command Line Tools.
#
# Why at all: since macOS 15.4 MediaRemote gives apps without Apple's
# entitlement nothing ("Now Playing" stays empty). Apple-signed
# /usr/bin/perl still may; the adapter loads this framework into perl and
# streams the data as JSON lines. So the app starts
#   /usr/bin/perl mediaremote-adapter.pl MediaRemoteAdapter.framework stream
# and does NOT link the framework - it is meant for perl.
#
# Rebuilt after the CMakeLists.txt of tag v0.7.7:
#   - all sources from src/adapter, src/private, src/utility as one
#     dynamic library in framework form (Versions/A, Info.plist, public
#     header)
#   - -fobjc-arc, -fvisibility=default (otherwise perl does not find the
#     functions via dlsym), Foundation, AppKit, UniformTypeIdentifiers
#   - x86_64 and arm64 as there (perl is universal)
#   - bundle ID com.vandenbe.MediaRemoteAdapter, version 0.1.0
#
# Usage: scripts/build-mediaremote-adapter.sh TARGET [IDENTITY]
#   creates TARGET/MediaRemoteAdapter.framework and
#   TARGET/mediaremote-adapter.pl. With IDENTITY the framework is signed
#   with it (as build.sh does), otherwise, or if that fails, ad-hoc as in
#   the original. MRA_TEST_CLIENT=1 also builds
#   TARGET/MediaRemoteAdapterTestClient (only for the "test" command, the
#   app does not need it).
set -eu

if [ $# -lt 1 ]; then
    echo "Aufruf: $0 ZIEL [IDENTITAET]" >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/extras/mediaremote-adapter"
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
IDENTITY=${2:-}

NAME=MediaRemoteAdapter
FW="$OUT/$NAME.framework"
VERSION=0.1.0
SHORT_VERSION=0.1
ARCHS="-arch arm64 -arch x86_64"
# As in Package.swift: the app only runs on macOS 26 and later.
MIN="-mmacosx-version-min=26.0"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# Foreign code, unchanged: its warnings (old block declarations without a
# prototype and the like) are not our problem and would clutter every
# output of build.sh. Errors stay errors.
CFLAGS="$ARCHS $MIN -O2 -fobjc-arc -fvisibility=default -w -I$SRC/include -I$SRC/src"

SOURCES="
adapter/env.m
adapter/get.m
adapter/globals.m
adapter/keys.m
adapter/now_playing.m
adapter/repeat.m
adapter/seek.m
adapter/send.m
adapter/shuffle.m
adapter/speed.m
adapter/stream.m
adapter/test.m
private/MediaRemote.m
utility/Debounce.m
utility/helpers.m
"

OBJECTS=""
for source in $SOURCES; do
    object="$WORK/$(echo "$source" | tr '/' '_' | sed 's/\.m$/.o/')"
    /usr/bin/clang $CFLAGS -c "$SRC/src/$source" -o "$object"
    OBJECTS="$OBJECTS $object"
done

# Framework layout as CMake does it with FRAMEWORK TRUE / FRAMEWORK_VERSION A.
rm -rf "$FW"
mkdir -p "$FW/Versions/A/Headers" "$FW/Versions/A/Resources"
# shellcheck disable=SC2086 # word splitting of ARCHS/OBJECTS is intended.
/usr/bin/clang $ARCHS $MIN -dynamiclib -fobjc-arc $OBJECTS \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name "@rpath/$NAME.framework/Versions/A/$NAME" \
    -o "$FW/Versions/A/$NAME"
cp "$SRC/include/MediaRemoteAdapter.h" "$FW/Versions/A/Headers/"
cat > "$FW/Versions/A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>English</string>
    <key>CFBundleExecutable</key>
    <string>$NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.vandenbe.$NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$NAME</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>$SHORT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CSResourcesFileMapped</key>
    <true/>
</dict>
</plist>
EOF
ln -s A "$FW/Versions/Current"
ln -s "Versions/Current/$NAME" "$FW/$NAME"
ln -s Versions/Current/Headers "$FW/Headers"
ln -s Versions/Current/Resources "$FW/Resources"

cp "$SRC/bin/mediaremote-adapter.pl" "$OUT/mediaremote-adapter.pl"

if [ "${MRA_TEST_CLIENT:-0}" = 1 ]; then
    /usr/bin/clang $ARCHS $MIN -O2 -fobjc-arc -w -I"$SRC/src/test" \
        "$SRC/src/test/main.m" "$SRC/src/test/NowPlayingTest.m" \
        -framework Foundation -framework MediaPlayer \
        -o "$OUT/${NAME}TestClient"
fi

# Signing: with the fixed identity if it exists and codesign works with
# it - otherwise ad-hoc as the CMake template does. perl loads either; the
# fixed identity only keeps the whole app's signature consistent.
sign() {
    if [ -n "$IDENTITY" ] &&
        security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\"" &&
        codesign --force --sign "$IDENTITY" "$1"; then
        return 0
    fi
    [ -n "$IDENTITY" ] && echo "Hinweis: $(basename "$1") ad-hoc signiert" >&2
    codesign --force --sign - "$1"
}
sign "$FW"
if [ -f "$OUT/${NAME}TestClient" ]; then sign "$OUT/${NAME}TestClient"; fi

echo "built: $FW"
