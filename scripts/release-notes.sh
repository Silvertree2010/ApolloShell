#!/bin/sh
set -eu

version=${1:?Fassung fehlt}
file=${2:-$(dirname "$0")/../CHANGELOG.md}

awk -v want="## [$version]" '
    index($0, want) == 1 { found = 1; next }
    found && /^## \[/    { exit }
    found                { print }
' "$file" | awk '
    NF { blank = 0; for (i = 0; i < held; i++) print ""; held = 0; print; seen = 1; next }
    seen { held++ }
'
