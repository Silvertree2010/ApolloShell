#!/usr/bin/env python3
"""Compares two folders of image samples (ApolloShell --render-reference /
--render, see testing.md 3).

Call: scripts/compare-renders.py <before> <after> [<diff folder>]
    [--channel-tolerance N] [--fraction-threshold F]
    [--area-threshold N] [--blur-sigma S] [--max-size-diff N]

For every PNG that lies in both folders: both images are downscaled by
2x2 averaging and Gaussian-blurred (testing.md 3.3), then compared. A
size difference of up to 4 pt per direction is padded with the smaller
image's top-left corner pixel colour; more is a failure. Pixels with a
channel deviation (including alpha) above the tolerance count as
different. A pair passes when the fraction of differing pixels AND the
largest 4-connected area of differing pixels (in absolute pixels, not
scaled by image size; the area is what separates localised changes on
images of very different sizes, testing.md 3.4) are below their
thresholds. With a diff folder, a side-by-side image (reference left,
after right, 16 px gap) is written for every pair, and a diff image
(differing pixels in red, padded the same way as the verdict) is
written in addition for every pair that fails.
Ends with 1 as soon as one pair fails or a file is missing on one side.
"""
import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

CHANNEL_TOLERANCE = 20
FRACTION_THRESHOLD = 0.10
LARGEST_COMPONENT_THRESHOLD = 300
BLUR_SIGMA = 1.5
MAX_SIZE_DIFF = 4
SIDE_BY_SIDE_GAP = 16


@dataclass
class ComparisonResult:
    passed: bool
    fraction: float
    largest_component: int
    size_mismatch: bool = False


def downscale_2x2(image: Image.Image) -> Image.Image:
    width, height = image.size
    target = (max(1, width // 2), max(1, height // 2))
    return image.resize(target, Image.BOX)


def pad_to_match(smaller: Image.Image, target_size: tuple[int, int]) -> Image.Image:
    corner = smaller.getpixel((0, 0))
    padded = Image.new("RGBA", target_size, corner)
    padded.paste(smaller, (0, 0))
    return padded


def difference_mask(a: Image.Image, b: Image.Image, channel_tolerance: int) -> Image.Image:
    delta = ImageChops.difference(a.convert("RGBA"), b.convert("RGBA"))
    channels = delta.split()
    largest = channels[0]
    for channel in channels[1:]:
        largest = ImageChops.lighter(largest, channel)
    return largest.point(lambda v: 255 if v > channel_tolerance else 0)


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


def prepare_pair(a: Image.Image, b: Image.Image, blur_sigma: float, max_size_diff: int):
    scaled_a = downscale_2x2(a.convert("RGBA"))
    scaled_b = downscale_2x2(b.convert("RGBA"))
    raw_a = a.convert("RGBA")
    raw_b = b.convert("RGBA")
    width_diff = abs(scaled_a.size[0] - scaled_b.size[0])
    height_diff = abs(scaled_a.size[1] - scaled_b.size[1])
    if scaled_a.size != scaled_b.size and (width_diff > max_size_diff or height_diff > max_size_diff):
        return scaled_a, scaled_b, True, raw_a, raw_b
    if scaled_a.size != scaled_b.size:
        target = (max(scaled_a.size[0], scaled_b.size[0]), max(scaled_a.size[1], scaled_b.size[1]))
        if scaled_a.size != target:
            scaled_a = pad_to_match(scaled_a, target)
        if scaled_b.size != target:
            scaled_b = pad_to_match(scaled_b, target)
        raw_target = (max(raw_a.size[0], raw_b.size[0]), max(raw_a.size[1], raw_b.size[1]))
        if raw_a.size != raw_target:
            raw_a = pad_to_match(raw_a, raw_target)
        if raw_b.size != raw_target:
            raw_b = pad_to_match(raw_b, raw_target)
    scaled_a = scaled_a.filter(ImageFilter.GaussianBlur(radius=blur_sigma))
    scaled_b = scaled_b.filter(ImageFilter.GaussianBlur(radius=blur_sigma))
    return scaled_a, scaled_b, False, raw_a, raw_b


def compare_images(a: Image.Image, b: Image.Image, channel_tolerance: int = CHANNEL_TOLERANCE,
                    fraction_threshold: float = FRACTION_THRESHOLD,
                    area_threshold: int = LARGEST_COMPONENT_THRESHOLD,
                    blur_sigma: float = BLUR_SIGMA,
                    max_size_diff: int = MAX_SIZE_DIFF) -> ComparisonResult:
    scaled_a, scaled_b, size_mismatch, _, _ = prepare_pair(a, b, blur_sigma, max_size_diff)
    if size_mismatch:
        return ComparisonResult(passed=False, fraction=1.0,
                                largest_component=scaled_a.size[0] * scaled_a.size[1],
                                size_mismatch=True)
    mask = difference_mask(scaled_a, scaled_b, channel_tolerance)
    total = scaled_a.size[0] * scaled_a.size[1]
    changed = total - mask.histogram()[0]
    fraction = changed / total if total else 0.0
    largest_component = largest_connected_component(mask) if changed else 0
    passed = fraction <= fraction_threshold and largest_component <= area_threshold
    return ComparisonResult(passed=passed, fraction=fraction, largest_component=largest_component)


def side_by_side(a: Image.Image, b: Image.Image) -> Image.Image:
    a = a.convert("RGBA")
    b = b.convert("RGBA")
    height = max(a.size[1], b.size[1])
    width = a.size[0] + SIDE_BY_SIDE_GAP + b.size[0]
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    canvas.paste(a, (0, 0))
    canvas.paste(b, (a.size[0] + SIDE_BY_SIDE_GAP, 0))
    return canvas


def compare(before: Path, after: Path, diff_dir: Path | None, a_image: Image.Image | None = None,
           b_image: Image.Image | None = None, **options) -> ComparisonResult:
    a = a_image if a_image is not None else Image.open(before).convert("RGBA")
    b = b_image if b_image is not None else Image.open(after).convert("RGBA")
    result = compare_images(a, b, **options)
    if diff_dir:
        diff_dir.mkdir(parents=True, exist_ok=True)
        side_by_side(a, b).save(diff_dir / f"{before.stem}-side-by-side.png")
    if result.size_mismatch:
        print(f"{before.name}: size {a.size} -> {b.size}")
        return result
    if result.passed:
        print(f"{before.name}: pass ({result.fraction:.4%}, largest area {result.largest_component})")
        return result
    print(f"{before.name}: fail ({result.fraction:.4%}, largest area {result.largest_component})")
    if diff_dir:
        sigma = options.get("blur_sigma", BLUR_SIGMA)
        tolerance = options.get("channel_tolerance", CHANNEL_TOLERANCE)
        max_size_diff = options.get("max_size_diff", MAX_SIZE_DIFF)
        scaled_a, scaled_b, _, raw_a, raw_b = prepare_pair(a, b, sigma, max_size_diff)
        mask = difference_mask(scaled_a, scaled_b, tolerance)
        mask = mask.resize(raw_a.size, Image.NEAREST)
        red = Image.new("RGBA", mask.size, (255, 0, 0, 255))
        Image.composite(red, raw_a, mask).save(diff_dir / before.name)
    return result


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("diff_dir", nargs="?")
    parser.add_argument("--channel-tolerance", type=int, default=CHANNEL_TOLERANCE)
    parser.add_argument("--fraction-threshold", type=float, default=FRACTION_THRESHOLD)
    parser.add_argument("--area-threshold", type=int, default=LARGEST_COMPONENT_THRESHOLD)
    parser.add_argument("--blur-sigma", type=float, default=BLUR_SIGMA)
    parser.add_argument("--max-size-diff", type=int, default=MAX_SIZE_DIFF)
    if len(argv) < 2:
        print(__doc__)
        return 2
    args = parser.parse_args(argv)
    before_dir, after_dir = Path(args.before), Path(args.after)
    diff_dir = Path(args.diff_dir) if args.diff_dir else None
    options = dict(channel_tolerance=args.channel_tolerance, fraction_threshold=args.fraction_threshold,
                    area_threshold=args.area_threshold, blur_sigma=args.blur_sigma,
                    max_size_diff=args.max_size_diff)
    ok = True
    before_names = set()
    for before in sorted(before_dir.glob("*.png")):
        before_names.add(before.name)
        after = after_dir / before.name
        if not after.exists():
            print(f"{before.name}: missing afterwards")
            ok = False
            continue
        ok = compare(before, after, diff_dir, **options).passed and ok
    for after in sorted(after_dir.glob("*.png")):
        if after.name not in before_names:
            print(f"{after.name}: no reference")
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
