#!/usr/bin/env python3
"""Compares two folders of image samples (ApolloShell --render-reference /
--render, see testing.md 3).

Call: scripts/compare-renders.py <before> <after> [<diff folder>]

For every PNG that lies in both folders: same size? Pixels with a channel
deviation above 8/255 count as different. A pair passes when at most 0.2 %
of the pixels differ AND the largest 4-connected area of differing pixels
is at most 24 pixels (testing.md 3.3). With a diff folder, an image is
written for every pair that fails, with the differing pixels in red.
Ends with 1 as soon as one pair fails or a file is missing on one side.
"""
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageChops

CHANNEL_TOLERANCE = 8
FRACTION_THRESHOLD = 0.002
LARGEST_COMPONENT_THRESHOLD = 24


@dataclass
class ComparisonResult:
    passed: bool
    fraction: float
    largest_component: int
    size_mismatch: bool = False


def difference_mask(a: Image.Image, b: Image.Image) -> Image.Image:
    delta = ImageChops.difference(a.convert("RGBA"), b.convert("RGBA"))
    channels = delta.split()
    largest = channels[0]
    for channel in channels[1:]:
        largest = ImageChops.lighter(largest, channel)
    return largest.point(lambda v: 255 if v > CHANNEL_TOLERANCE else 0)


def largest_connected_component(mask: Image.Image) -> int:
    width, height = mask.size
    pixels = mask.load()
    seen = bytearray(width * height)
    largest = 0
    for start_y in range(height):
        for start_x in range(width):
            index = start_y * width + start_x
            if seen[index] or pixels[start_x, start_y] == 0:
                continue
            stack = [(start_x, start_y)]
            seen[index] = 1
            size = 0
            while stack:
                x, y = stack.pop()
                size += 1
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < width and 0 <= ny < height:
                        neighbour = ny * width + nx
                        if not seen[neighbour] and pixels[nx, ny] != 0:
                            seen[neighbour] = 1
                            stack.append((nx, ny))
            largest = max(largest, size)
    return largest


def compare_images(a: Image.Image, b: Image.Image) -> ComparisonResult:
    if a.size != b.size:
        return ComparisonResult(passed=False, fraction=1.0, largest_component=a.size[0] * a.size[1],
                                size_mismatch=True)
    mask = difference_mask(a, b)
    total = a.size[0] * a.size[1]
    changed = total - mask.histogram()[0]
    fraction = changed / total if total else 0.0
    largest_component = largest_connected_component(mask) if changed else 0
    passed = fraction <= FRACTION_THRESHOLD and largest_component <= LARGEST_COMPONENT_THRESHOLD
    return ComparisonResult(passed=passed, fraction=fraction, largest_component=largest_component)


def compare(before: Path, after: Path, diff_dir: Path | None, a_image: Image.Image | None = None,
           b_image: Image.Image | None = None) -> ComparisonResult:
    a = a_image if a_image is not None else Image.open(before).convert("RGBA")
    b = b_image if b_image is not None else Image.open(after).convert("RGBA")
    result = compare_images(a, b)
    if result.size_mismatch:
        print(f"{before.name}: size {a.size} -> {b.size}")
        return result
    if result.passed:
        print(f"{before.name}: pass ({result.fraction:.4%}, largest area {result.largest_component})")
        return result
    print(f"{before.name}: fail ({result.fraction:.4%}, largest area {result.largest_component})")
    if diff_dir:
        diff_dir.mkdir(parents=True, exist_ok=True)
        mask = difference_mask(a, b)
        red = Image.new("RGBA", a.size, (255, 0, 0, 255))
        Image.composite(red, a.convert("RGBA"), mask).save(diff_dir / before.name)
    return result


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2
    before_dir, after_dir = Path(argv[0]), Path(argv[1])
    diff_dir = Path(argv[2]) if len(argv) > 2 else None
    ok = True
    before_names = set()
    for before in sorted(before_dir.glob("*.png")):
        before_names.add(before.name)
        after = after_dir / before.name
        if not after.exists():
            print(f"{before.name}: missing afterwards")
            ok = False
            continue
        ok = compare(before, after, diff_dir).passed and ok
    for after in sorted(after_dir.glob("*.png")):
        if after.name not in before_names:
            print(f"{after.name}: no reference")
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
