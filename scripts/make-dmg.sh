#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
if [ -z "${SDKROOT:-}" ] && [ -d "$SDK" ]; then
    export SDKROOT="$SDK"
fi

ARCHS=${ARCHS:-"arm64 x86_64"}
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)
OUT=build/dist
DMG="dist/ApolloShell-$VERSION.dmg"

rm -rf "$OUT"
mkdir -p "$OUT" dist

BINARIES=""
for arch in $ARCHS; do
    set -- -c release --product ApolloShell --triple "$arch-apple-macosx26.0" --scratch-path ".build/release-$arch"
    swift build "$@"
    bin="$(swift build "$@" --show-bin-path)/ApolloShell"
    lipo "$bin" -verify_arch "$arch"
    BINARIES="$BINARIES $bin"
    [ -n "${SPARKLE_FRAMEWORK:-}" ] || SPARKLE_FRAMEWORK="$(dirname "$bin")/Sparkle.framework"
done
export SPARKLE_FRAMEWORK

lipo -create $BINARIES -output "$OUT/ApolloShell"
lipo -info "$OUT/ApolloShell"

scripts/assemble-app.sh "$OUT/ApolloShell" "$OUT/ApolloShell.app"

STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$OUT/ApolloShell.app" "$STAGE/ApolloShell.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "ApolloShell $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
hdiutil verify "$DMG"

echo "created: $DMG ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG"
