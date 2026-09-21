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
#   SIGN_IDENTITY  code-signing identity. Default: "ApolloShell Release
#                  Signing" if it is in the keychain (the maintainer's Mac),
#                  then "Launcher Local Signing" (scripts/setup-signing.sh),
#                  otherwise ad-hoc. Set it to an empty string to force
#                  ad-hoc signing.
#   BUILD_NUMBER   CFBundleVersion. Default: number of git commits, or 1
#                  outside a git checkout (e.g. a release tarball).
#   HOMEBREW_BUILD set to 1 by the Homebrew formula. It drops a marker file
#                  into the bundle; the app reads it and then never updates
#                  itself, because the Cellar copy belongs to Homebrew
#                  (Sources/ApolloShellCore/InstallKind.swift). The marker has
#                  to be written before signing, or the signature would not
#                  match the bundle any more.
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

has_identity() {
    security find-identity -p codesigning 2>/dev/null | grep -q "\"$1\""
}

if [ "${SIGN_IDENTITY+set}" = set ]; then
    IDENTITY=$SIGN_IDENTITY
elif has_identity "ApolloShell Release Signing"; then
    # The release certificate first: an Accessibility grant given to a
    # release (installed from the DMG or updated by Sparkle) then also holds
    # for a local build, and the other way round. With the local one, every
    # switch between a release and a local build lost the grant (21.09.).
    IDENTITY="ApolloShell Release Signing"
else
    IDENTITY="Launcher Local Signing"
fi

# Decide once what everything is signed with: the app, Sparkle's parts and
# the Now Playing helper have to carry the same signature.
if [ "$IDENTITY" = "-" ]; then
    # Explicitly ad-hoc (CI, rendered samples): no lookup, no error.
    echo "signing ad-hoc (SIGN_IDENTITY=-)"
elif [ -n "$IDENTITY" ] && has_identity "$IDENTITY"; then
    echo "signing with: $IDENTITY"
elif [ "${SIGN_IDENTITY+set}" = set ] && [ -n "$SIGN_IDENTITY" ]; then
    # Explicitly asked for and not there: stop. Quietly signing ad-hoc
    # would mean, in a release, that every Accessibility grant is gone
    # after the update - and only the users would notice.
    echo "signing identity not in the keychain: $SIGN_IDENTITY" >&2
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

# Now Playing helper (extras/mediaremote-adapter, see MediaModel.swift): the
# framework goes to Frameworks (nested code, signed before the app), the perl
# script to Resources. The framework is always built for arm64 and x86_64.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM
"$ROOT/scripts/build-mediaremote-adapter.sh" "$WORK/mediaremote-adapter" "$IDENTITY"
ditto "$WORK/mediaremote-adapter/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
cp "$WORK/mediaremote-adapter/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"

# Sparkle (self-updating): SwiftPM puts the framework next to the
# executable. It is universal already (arm64 + x86_64), so one copy is
# enough, for the universal DMG too. SPARKLE_FRAMEWORK overrides where it
# is looked for.
SPARKLE=${SPARKLE_FRAMEWORK:-$(dirname "$BINARY")/Sparkle.framework}
if [ ! -d "$SPARKLE" ]; then
    echo "Sparkle.framework missing: $SPARKLE (swift build fetches it)" >&2
    exit 1
fi
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
# It runs the same without headers and module maps; only the compiler needs those.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Headers" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/PrivateHeaders" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Modules" \
    "$APP/Contents/Frameworks/Sparkle.framework/Headers" \
    "$APP/Contents/Frameworks/Sparkle.framework/PrivateHeaders" \
    "$APP/Contents/Frameworks/Sparkle.framework/Modules"
# SwiftPM builds with search paths into the build folder; in the bundle the
# framework sits next to the executable in Frameworks.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/ApolloShell" 2>/dev/null || true

# Sparkle brings its own programs (Updater.app, Autoupdate, two XPC
# services). Nested code is signed before the outer code, otherwise the
# app's signature no longer matches its contents.
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
