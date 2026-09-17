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

if [ "${SIGN_IDENTITY+set}" = set ]; then
    IDENTITY=$SIGN_IDENTITY
else
    IDENTITY="Launcher Local Signing"
fi

# Einmal entscheiden, womit alles signiert wird: die App, Sparkles Teile und
# der Now-Playing-Helfer muessen dieselbe Signatur tragen.
if [ -n "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    echo "signing with: $IDENTITY"
elif [ "${SIGN_IDENTITY+set}" = set ] && [ -n "$SIGN_IDENTITY" ]; then
    # Ausdruecklich verlangt und nicht da: abbrechen. Still ad-hoc zu
    # signieren hiesse im Release, dass jede Bedienungshilfen-Freigabe nach
    # dem Update weg ist - und das faellt erst den Nutzern auf.
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

# Now Playing helper (extras/mediaremote-adapter, see MediaModel.swift): the
# framework goes to Frameworks (nested code, signed before the app), the perl
# script to Resources. The framework is always built for arm64 and x86_64.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM
"$ROOT/scripts/build-mediaremote-adapter.sh" "$WORK/mediaremote-adapter" "$IDENTITY"
ditto "$WORK/mediaremote-adapter/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
cp "$WORK/mediaremote-adapter/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"

# Sparkle (Selbstaktualisierung): SwiftPM legt das Rahmenwerk neben das
# Programm. Es ist bereits universell (arm64 + x86_64), deshalb genuegt eine
# Kopie, auch fuer das universelle DMG. SPARKLE_FRAMEWORK ueberschreibt den
# Fundort.
SPARKLE=${SPARKLE_FRAMEWORK:-$(dirname "$BINARY")/Sparkle.framework}
if [ ! -d "$SPARKLE" ]; then
    echo "Sparkle.framework fehlt: $SPARKLE (swift build laeuft es mit)" >&2
    exit 1
fi
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
# Ohne Header und Modulkarten laeuft es genauso; die braucht nur der Compiler.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Headers" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/PrivateHeaders" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Modules" \
    "$APP/Contents/Frameworks/Sparkle.framework/Headers" \
    "$APP/Contents/Frameworks/Sparkle.framework/PrivateHeaders" \
    "$APP/Contents/Frameworks/Sparkle.framework/Modules"
# SwiftPM baut mit Suchpfaden auf den Bauordner; im Bundle liegt das
# Rahmenwerk daneben in Frameworks.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/ApolloShell" 2>/dev/null || true

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

# Sparkle bringt eigene Programme mit (Updater.app, Autoupdate, zwei
# XPC-Dienste). Verschachtelter Code wird vor dem Aeusseren signiert, sonst
# passt die Signatur der App nicht mehr zu ihrem Inhalt.
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
