import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from PIL import Image

import importlib
compare_renders = importlib.import_module("compare-renders")


def solid(size, color):
    return Image.new("RGBA", size, color)


def with_patch(base, box, color):
    image = base.copy()
    patch = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), color)
    image.paste(patch, box[:2])
    return image


class CompareRendersTests(unittest.TestCase):
    def test_identical_images_pass(self):
        a = solid((40, 40), (10, 10, 10, 255))
        b = a.copy()
        result = compare_renders.compare_images(a, b)
        self.assertTrue(result.passed)
        self.assertEqual(result.fraction, 0.0)
        self.assertEqual(result.largest_component, 0)

    def test_scattered_single_pixels_under_threshold_pass(self):
        a = solid((100, 100), (10, 10, 10, 255))
        b = a.copy()
        pixels = b.load()
        for i in range(15):
            pixels[i * 6, i * 6] = (255, 255, 255, 255)
        result = compare_renders.compare_images(a, b)
        self.assertTrue(result.passed)
        self.assertEqual(result.largest_component, 1)

    def test_large_connected_block_fails(self):
        a = solid((100, 100), (10, 10, 10, 255))
        b = with_patch(a, (10, 10, 20, 20), (255, 255, 255, 255))
        result = compare_renders.compare_images(a, b)
        self.assertFalse(result.passed)
        self.assertEqual(result.largest_component, 100)

    def test_many_small_blocks_over_fraction_threshold_fail(self):
        a = solid((100, 100), (10, 10, 10, 255))
        b = a.copy()
        for row in range(0, 100, 4):
            for col in range(0, 100, 4):
                b = with_patch(b, (col, row, col + 2, row + 2), (255, 255, 255, 255))
        result = compare_renders.compare_images(a, b)
        self.assertFalse(result.passed)
        self.assertLessEqual(result.largest_component, 24)

    def test_alpha_only_difference_is_detected(self):
        a = Image.new("RGBA", (20, 20), (10, 10, 10, 255))
        b = Image.new("RGBA", (20, 20), (10, 10, 10, 0))
        result = compare_renders.compare_images(a, b)
        self.assertFalse(result.passed)

    def test_size_mismatch_reports_failure_without_exception(self):
        a = solid((40, 40), (10, 10, 10, 255))
        b = solid((41, 40), (10, 10, 10, 255))
        result = compare_renders.compare(Path("a.png"), Path("b.png"), None, a_image=a, b_image=b)
        self.assertFalse(result.passed)

    def test_extra_file_without_reference_reported_per_pair(self):
        import tempfile
        with tempfile.TemporaryDirectory() as before, tempfile.TemporaryDirectory() as after:
            before_path, after_path = Path(before), Path(after)
            solid((10, 10), (0, 0, 0, 255)).save(before_path / "both.png")
            solid((10, 10), (0, 0, 0, 255)).save(after_path / "both.png")
            solid((10, 10), (0, 0, 0, 255)).save(after_path / "only-after.png")
            exit_code = compare_renders.main([str(before_path), str(after_path)])
            self.assertEqual(exit_code, 1)

    def test_missing_file_reported_per_pair(self, ):
        import tempfile
        with tempfile.TemporaryDirectory() as before, tempfile.TemporaryDirectory() as after:
            before_path, after_path = Path(before), Path(after)
            solid((10, 10), (0, 0, 0, 255)).save(before_path / "only-before.png")
            solid((10, 10), (0, 0, 0, 255)).save(before_path / "both.png")
            solid((10, 10), (0, 0, 0, 255)).save(after_path / "both.png")
            exit_code = compare_renders.main([str(before_path), str(after_path)])
            self.assertEqual(exit_code, 1)


if __name__ == "__main__":
    unittest.main()
