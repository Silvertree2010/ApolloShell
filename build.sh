#!/bin/sh
set -eu
cd "$(dirname "$0")"

if [ -f .local.env ]; then
    . ./.local.env
fi

export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk

swift build -c release --product ApolloShell

APP="build/ApolloShell.app"
scripts/assemble-app.sh .build/release/ApolloShell "$APP"

DEST="$HOME/Applications/ApolloShell.app"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$APP" "$DEST"
echo "installiert: $DEST"

LABEL=${APOLLOSHELL_LAUNCHD_LABEL:-}
if [ -n "$LABEL" ] && launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$(id -u)/$LABEL" && echo "neu gestartet (launchd: $LABEL)"
elif pgrep -x ApolloShell >/dev/null; then
    pkill -TERM -x ApolloShell
    i=0
    while pgrep -x ApolloShell >/dev/null && [ "$i" -lt 50 ]; do
        sleep 0.1
        i=$((i + 1))
    done
    open "$DEST" && echo "neu gestartet"
fi
