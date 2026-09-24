#!/usr/bin/env python3
from PIL import Image
from pathlib import Path

root = Path(__file__).resolve().parent.parent
base = Image.open(root / "docs/images/icon.png").convert("RGBA")
base.resize((48, 48), Image.LANCZOS).save(
    root / "docs/favicon.ico", format="ICO", sizes=[(48, 48), (32, 32), (16, 16)]
)
print("wrote docs/favicon.ico")
