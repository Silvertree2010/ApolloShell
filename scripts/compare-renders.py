#!/usr/bin/env python3
"""Vergleicht zwei Ordner mit Bildproben (ApolloShell --render-dashboard).

Aufruf: scripts/compare-renders.py <vorher> <nachher> [<diff-ordner>]

Fuer jede PNG, die in beiden Ordnern liegt: gleiche Groesse? wie viele
Pixel weichen ab (irgendein Kanal um mehr als 8 von 255)? Mit Diff-Ordner
wird fuer jede abweichende Datei ein Bild geschrieben, abweichende Pixel rot.
Endet mit 1, sobald eine Datei abweicht oder fehlt.
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops

TOLERANCE = 8


def compare(before: Path, after: Path, diff_dir: Path | None) -> bool:
    a = Image.open(before).convert("RGBA")
    b = Image.open(after).convert("RGBA")
    if a.size != b.size:
        print(f"{before.name}: Groesse {a.size} -> {b.size}")
        return False
    delta = ImageChops.difference(a, b)
    # Groesste Abweichung ueber alle Kanaele (auch nur Alpha zaehlt).
    channels = delta.split()
    largest = channels[0]
    for channel in channels[1:]:
        largest = ImageChops.lighter(largest, channel)
    mask = largest.point(lambda v: 255 if v > TOLERANCE else 0)
    changed = a.size[0] * a.size[1] - mask.histogram()[0]
    if changed == 0:
        print(f"{before.name}: gleich")
        return True
    print(f"{before.name}: {changed} Pixel abweichend")
    if diff_dir:
        diff_dir.mkdir(parents=True, exist_ok=True)
        red = Image.new("RGBA", a.size, (255, 0, 0, 255))
        Image.composite(red, a.convert("RGBA"), mask).save(diff_dir / before.name)
    return False


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    before_dir, after_dir = Path(sys.argv[1]), Path(sys.argv[2])
    diff_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else None
    ok = True
    for before in sorted(before_dir.glob("*.png")):
        after = after_dir / before.name
        if not after.exists():
            print(f"{before.name}: fehlt nachher")
            ok = False
            continue
        ok = compare(before, after, diff_dir) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
