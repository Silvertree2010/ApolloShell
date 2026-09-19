#!/bin/sh
# Builds a release disk image: dist/ApolloShell-<version>.dmg with
# ApolloShell.app and a shortcut to /Applications.
#
# Universal by default: one release build per architecture (each in its own
# scratch path - with SwiftPM's build system on Swift 6.4 every triple writes
# to the same .build/out/Products/Release and would overwrite the other),
# joined with lipo. The Now Playing helper framework is always universal.
# ARCHS="arm64" ./scripts/make-dmg.sh builds an Apple-silicon-only image.
#
# Signing: see scripts/assemble-app.sh (SIGN_IDENTITY, default: local
# identity if present, else ad-hoc). The image is not notarised - users have
# to confirm the first launch under System Settings > Privacy & Security.
#
# Installs nothing, launches nothing.
set -eu
cd "$(dirname "$0")/.."

# Same SDK pin as build.sh/test.sh (newer Command Line Tools default to an SDK
# that does not match their compiler).
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
    # As an XCFramework Sparkle is universal already; one copy is enough
    # for both architectures.
    [ -n "${SPARKLE_FRAMEWORK:-}" ] || SPARKLE_FRAMEWORK="$(dirname "$bin")/Sparkle.framework"
done
export SPARKLE_FRAMEWORK

# shellcheck disable=SC2086 # word splitting of BINARIES is intended
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
