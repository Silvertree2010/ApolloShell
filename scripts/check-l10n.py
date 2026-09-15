#!/usr/bin/env python3
"""Findet deutsche UI-Literale in Sources/ ohne englischen Eintrag unter
Support/Localization/en/*.strings.

Erfasst: Text(...), Button(...), Label(...), Toggle(...), Picker(...),
Section(...), .help(...) und Parameter, die erkennbar eine
LocalizedStringKey annehmen (title:, label:, header:, footer:, ...: "...").
Nur das erste String-Literal eines solchen Aufrufs zaehlt (SwiftUI liest nur
das als Uebersetzungsschluessel; ein zweites Literal ist meist ein Systembild
oder eine Aktion).

Ignoriert: Text(verbatim:), String(...), Logger-Aufrufe, Kommentare,
Literale ganz ohne deutschen Buchstaben/Wortcharakter (SF-Symbol-Namen,
JSON-Schluessel etc. - grobe Heuristik, siehe l10n-ignore.txt fuer den Rest).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
STRINGS_DIR = ROOT / "Support" / "Localization" / "en"
IGNORE_FILE = ROOT / "scripts" / "l10n-ignore.txt"

# Aufrufe/Labels, die SwiftUI als LocalizedStringKey liest.
CALL_RE = re.compile(
    r'(?<![.\w])(Text|Button|Label|Toggle|Picker|Section)\(\s*"((?:[^"\\]|\\.)*)"'
)
HELP_RE = re.compile(r'\.help\(\s*"((?:[^"\\]|\\.)*)"')
# title:/label:/header:/footer:/placeholder: "..." als eigenstaendiges
# LocalizedStringKey-Argument (nicht String(...)).
KEYWORD_RE = re.compile(
    r'\b(?:title|label|header|footer|placeholder)\s*:\s*"((?:[^"\\]|\\.)*)"'
)
VERBATIM_RE = re.compile(r'Text\(\s*verbatim:')


def normalize(s: str) -> str:
    """Macht Interpolationen und Format-Platzhalter vergleichbar: \\(...)
    (auch mit verschachtelten Klammern) im Quelltext und %@/%lld/%lf/%d im
    .strings-Wert werden beide zu einem einzelnen Platzhalter '#'."""
    out: list[str] = []
    i = 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s) and s[i + 1] == "(":
            depth = 1
            j = i + 2
            while j < len(s) and depth > 0:
                if s[j] == "(":
                    depth += 1
                elif s[j] == ")":
                    depth -= 1
                j += 1
            out.append("#")
            i = j
        elif s[i] == "%":
            m = re.match(r"%(?:lld|lf|ld|d|@|lu)", s[i:])
            if m:
                out.append("#")
                i += len(m.group(0))
            else:
                out.append(s[i])
                i += 1
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def load_translated() -> set[str]:
    keys: set[str] = set()
    if not STRINGS_DIR.is_dir():
        return keys
    entry_re = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')
    for f in sorted(STRINGS_DIR.glob("*.strings")):
        for line in f.read_text(encoding="utf-8").splitlines():
            m = entry_re.match(line)
            if m:
                keys.add(m.group(1))
    return keys


def load_ignore() -> set[str]:
    if not IGNORE_FILE.is_file():
        return set()
    lines = IGNORE_FILE.read_text(encoding="utf-8").splitlines()
    return {ln for ln in lines if ln and not ln.startswith("#")}


def outside_interpolation(s: str) -> str:
    """`s` ohne den Code in \\(...) (auch verschachtelte Klammern) - nur der
    literale Text bleibt, den looks_like_prose beurteilen soll."""
    out: list[str] = []
    i = 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s) and s[i + 1] == "(":
            depth = 1
            j = i + 2
            while j < len(s) and depth > 0:
                if s[j] == "(":
                    depth += 1
                elif s[j] == ")":
                    depth -= 1
                j += 1
            i = j
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def looks_like_prose(s: str) -> bool:
    """Grobe Heuristik: enthaelt ausserhalb von Interpolationen Buchstaben
    und entweder ein Leerzeichen oder einen Umlaut/ess-zett - schliesst
    SF-Symbol-Namen ("gear"), Kennungen ("de", "en"), reine
    Interpolationen ("\\(a) \\(b)") und leere/Formatstrings weitgehend aus."""
    literal = outside_interpolation(s)
    if not literal or not any(c.isalpha() for c in literal):
        return False
    if " " in literal:
        return True
    return any(c in literal for c in "äöüÄÖÜß")


def main() -> int:
    translated = load_translated()
    translated_normalized = {normalize(k) for k in translated}
    ignored = load_ignore()
    missing: list[tuple[str, int, str]] = []

    for path in sorted(SOURCES.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        for lineno, line in enumerate(lines, start=1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            if VERBATIM_RE.search(line):
                continue
            literals: list[str] = []
            m = CALL_RE.search(line)
            if m:
                literals.append(m.group(2))
            for m in HELP_RE.finditer(line):
                literals.append(m.group(1))
            for m in KEYWORD_RE.finditer(line):
                literals.append(m.group(1))
            for lit in literals:
                if not looks_like_prose(lit):
                    continue
                if lit in translated or lit in ignored:
                    continue
                if "\\(" in lit and normalize(lit) in translated_normalized:
                    continue
                missing.append((str(path.relative_to(ROOT)), lineno, lit))

    if missing:
        print(f"{len(missing)} UI-Literal(e) ohne englischen Eintrag:")
        for file, lineno, lit in missing:
            print(f"  {file}:{lineno}: \"{lit}\"")
        return 1

    print("check-l10n: keine fehlenden Uebersetzungen gefunden")
    return 0


if __name__ == "__main__":
    sys.exit(main())
