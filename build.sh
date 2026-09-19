#!/bin/sh
# Development build: builds ApolloShell.app, installs it into
# ~/Applications and restarts a running instance. No Xcode needed. The
# bundle is put together by scripts/assemble-app.sh, the same script the
# DMG and the Homebrew formula use.
#
# How it restarts afterwards:
# - APOLLOSHELL_LAUNCHD_LABEL set and that launchd agent loaded:
#   `launchctl kickstart -k`. Machine-specific values live in .local.env
#   (not in the repo), e.g. APOLLOSHELL_LAUNCHD_LABEL=org.example.apolloshell
# - Otherwise, if ApolloShell is running: quit it cleanly (SIGTERM, which
#   brings Apple's Dock back) and open the installed bundle.
# - If nothing is running, build.sh starts nothing either.
set -eu
cd "$(dirname "$0")"

if [ -f .local.env ]; then
    . ./.local.env
fi

# SDK pinned to macOS 26 (reason in test.sh: otherwise CLT 26.6 picks the
# macOS 27 SDK, which does not match the compiler).
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk

swift build -c release --product ApolloShell

APP="build/ApolloShell.app"
scripts/assemble-app.sh .build/release/ApolloShell "$APP"

DEST="$HOME/Applications/ApolloShell.app"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$APP" "$DEST"
echo "installed: $DEST"

LABEL=${APOLLOSHELL_LAUNCHD_LABEL:-}
if [ -n "$LABEL" ] && launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$(id -u)/$LABEL" && echo "restarted (launchd: $LABEL)"
elif pgrep -x ApolloShell >/dev/null; then
    pkill -TERM -x ApolloShell
    i=0
    while pgrep -x ApolloShell >/dev/null && [ "$i" -lt 50 ]; do
        sleep 0.1
        i=$((i + 1))
    done
    open "$DEST" && echo "restarted"
fi
