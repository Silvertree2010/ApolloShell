#!/bin/sh
# Schneidet den Abschnitt einer Fassung aus CHANGELOG.md heraus, fuer die
# Notizen eines GitHub-Releases. Ohne das stand dort nur ein Verweis - und
# der war deutsch, obwohl alles andere am Repo englisch ist.
#
#   scripts/release-notes.sh 0.1.2.2 [CHANGELOG.md]
set -eu

version=${1:?Fassung fehlt}
file=${2:-$(dirname "$0")/../CHANGELOG.md}

awk -v want="## [$version]" '
    index($0, want) == 1 { found = 1; next }
    found && /^## \[/    { exit }
    found                { print }
' "$file" | awk '
    # Fuehrende und abschliessende Leerzeilen weg
    NF { blank = 0; for (i = 0; i < held; i++) print ""; held = 0; print; seen = 1; next }
    seen { held++ }
'
