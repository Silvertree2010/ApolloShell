#!/bin/sh
# Assembles and signs ApolloShell.app from an already built binary.
# Shared by scripts/make-dmg.sh and the Homebrew formula
# (packaging/homebrew/apolloshell.rb). Installs nothing, launches nothing.
#
# Usage: scripts/assemble-app.sh BINARY APP
#   BINARY  the ApolloShell executable (thin or universal)
#   APP     where to create the bundle, e.g. build/dist/ApolloShell.app
#
# Environment:
#   SIGN_IDENTITY  code-signing identity. Default "Launcher Local Signing"
#                  (created by scripts/setup-signing.sh) if it exists in the
#                  keychain, otherwise ad-hoc. Set it to an empty string to
#                  force ad-hoc signing.
#   BUILD_NUMBER   CFBundleVersion. Default: number of git commits, or 1
#                  outside a git checkout (e.g. a release tarball).
#
# Why a fixed identity matters: macOS ties the Accessibility grant to the
# app's code signature. Ad-hoc signatures change with every build, so the
# grant would have to be given again after each update. See
# scripts/setup-signing.sh.
set -eu

if [ $# -ne 2 ]; then
    echo "usage: $0 BINARY APP" >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BINARY=$1
APP=$2
PLIST="$ROOT/Support/Info.plist"
PLISTBUDDY=/usr/libexec/PlistBuddy

if [ "${SIGN_IDENTITY+set}" = set ]; then
    IDENTITY=$SIGN_IDENTITY
else
    IDENTITY="Launcher Local Signing"
fi

if [ -z "${BUILD_NUMBER:-}" ]; then
    BUILD_NUMBER=$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)
fi

BUNDLE_ID=$("$PLISTBUDDY" -c 'Print :CFBundleIdentifier' "$PLIST")

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/ApolloShell"
cp "$PLIST" "$APP/Contents/Info.plist"
"$PLISTBUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Now Playing helper (extras/mediaremote-adapter, see MediaModel.swift): the
# framework goes to Frameworks (nested code, signed before the app), the perl
# script to Resources. The framework is always built for arm64 and x86_64.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM
"$ROOT/scripts/build-mediaremote-adapter.sh" "$WORK/mediaremote-adapter" "$IDENTITY"
ditto "$WORK/mediaremote-adapter/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
cp "$WORK/mediaremote-adapter/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"

# Lokalisierung: de.lproj bleibt leer (Deutsch ist der Code selbst - die
# String-Literale brauchen keine Uebersetzungstabelle), en.lproj bekommt alle
# Support/Localization/en/*.strings zusammengefuegt.
mkdir -p "$APP/Contents/Resources/de.lproj" "$APP/Contents/Resources/en.lproj"
: > "$APP/Contents/Resources/de.lproj/Localizable.strings"
EN_STRINGS="$APP/Contents/Resources/en.lproj/Localizable.strings"
: > "$EN_STRINGS"
for f in "$ROOT"/Support/Localization/en/*.strings; do
    [ -e "$f" ] || continue
    cat "$f" >> "$EN_STRINGS"
    printf '\n' >> "$EN_STRINGS"
done
if ! plutil -lint "$EN_STRINGS" >/dev/null; then
    echo "fehlerhafte Lokalisierung: $EN_STRINGS" >&2
    exit 1
fi

if [ -n "$IDENTITY" ] &&
    security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\"" &&
    codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"; then
    echo "signed with: $IDENTITY"
else
    echo "note: ad-hoc signature - the Accessibility grant will not survive the next build (scripts/setup-signing.sh)" >&2
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

codesign --verify --deep --strict "$APP"
echo "assembled: $APP (build $BUILD_NUMBER)"
