#!/bin/sh
# Findet UI-Literale (Text/Button/Label/Toggle/Picker/Section/.help/
# LocalizedStringKey) ohne englischen Eintrag in Support/Localization/en.
# Ausnahmen: scripts/l10n-ignore.txt (ein Literal pro Zeile).
set -eu
cd "$(dirname "$0")/.."
exec python3 scripts/check-l10n.py
