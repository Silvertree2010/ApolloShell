#!/bin/sh
# Cuts the section of one version out of CHANGELOG.md, for the notes of a
# GitHub release. Without it the notes were only a link to the file.
#
#   scripts/release-notes.sh 0.1.2.2 [CHANGELOG.md]
set -eu

version=${1:?version missing}
file=${2:-$(dirname "$0")/../CHANGELOG.md}

awk -v want="## [$version]" '
    index($0, want) == 1 { found = 1; next }
    found && /^## \[/    { exit }
    found                { print }
' "$file" | awk '
    # Drop leading and trailing blank lines
    NF { blank = 0; for (i = 0; i < held; i++) print ""; held = 0; print; seen = 1; next }
    seen { held++ }
'
