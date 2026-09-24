#!/bin/sh
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

if [ "$IDENTITY" = "-" ]; then
    echo "signing ad-hoc (SIGN_IDENTITY=-)"
elif [ -n "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    echo "signing with: $IDENTITY"
elif [ "${SIGN_IDENTITY+set}" = set ] && [ -n "$SIGN_IDENTITY" ]; then
    echo "Signier-Identitaet nicht im Schluesselbund: $SIGN_IDENTITY" >&2
    exit 1
else
    echo "note: ad-hoc signature - the Accessibility grant will not survive the next build (scripts/setup-signing.sh)" >&2
    IDENTITY=-
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

if [ "${HOMEBREW_BUILD:-}" = "1" ]; then
    echo "Installed by Homebrew. Updates go through: brew upgrade apolloshell" \
        > "$APP/Contents/Resources/installed-by-homebrew"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM
"$ROOT/scripts/build-mediaremote-adapter.sh" "$WORK/mediaremote-adapter" "$IDENTITY"
ditto "$WORK/mediaremote-adapter/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
cp "$WORK/mediaremote-adapter/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"

SPARKLE=${SPARKLE_FRAMEWORK:-$(dirname "$BINARY")/Sparkle.framework}
if [ ! -d "$SPARKLE" ]; then
    echo "Sparkle.framework fehlt: $SPARKLE (swift build laeuft es mit)" >&2
    exit 1
fi
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Headers" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/PrivateHeaders" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Modules" \
    "$APP/Contents/Frameworks/Sparkle.framework/Headers" \
    "$APP/Contents/Frameworks/Sparkle.framework/PrivateHeaders" \
    "$APP/Contents/Frameworks/Sparkle.framework/Modules"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/ApolloShell" 2>/dev/null || true

SPARKLE_IN_APP="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in \
    "$SPARKLE_IN_APP/XPCServices/Downloader.xpc" \
    "$SPARKLE_IN_APP/XPCServices/Installer.xpc" \
    "$SPARKLE_IN_APP/Updater.app" \
    "$SPARKLE_IN_APP/Autoupdate"; do
    [ -e "$part" ] || continue
    codesign --force --sign "$IDENTITY" --timestamp=none "$part"
done
codesign --force --sign "$IDENTITY" --timestamp=none "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"

codesign --verify --deep --strict "$APP"
echo "assembled: $APP (build $BUILD_NUMBER)"
