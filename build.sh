#!/bin/sh
# Entwicklungs-Build: baut ApolloShell.app, installiert es nach
# ~/Applications und startet eine laufende Instanz neu. Kein Xcode noetig.
# Das Bundle setzt scripts/assemble-app.sh zusammen, dasselbe Skript wie fuer
# DMG und Homebrew-Formel.
#
# Neustart danach:
# - APOLLOSHELL_LAUNCHD_LABEL gesetzt und dieser launchd-Agent geladen:
#   `launchctl kickstart -k`. Rechner-eigene Werte stehen in .local.env
#   (nicht im Repo), z. B. APOLLOSHELL_LAUNCHD_LABEL=org.example.apolloshell
# - Sonst, wenn ApolloShell laeuft: sauber beenden (SIGTERM, stellt Apples
#   Dock wieder her) und das installierte Bundle oeffnen.
# - Laeuft nichts, startet build.sh auch nichts.
set -eu
cd "$(dirname "$0")"

if [ -f .local.env ]; then
    . ./.local.env
fi

# SDK fest auf macOS 26 (Begruendung in test.sh: CLT 26.6 stellt sonst das
# macOS-27-SDK ein, das nicht zum Compiler passt).
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
