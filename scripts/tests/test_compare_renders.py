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
        a = solid((80, 80), (10, 10, 10, 255))
        b = a.copy()
        result = compare_renders.compare_images(a, b)
        self.assertTrue(result.passed)
        self.assertEqual(result.fraction, 0.0)
        self.assertEqual(result.largest_component, 0)

    def test_small_shift_passes(self):
        a = solid((120, 120), (10, 10, 10, 255))
        a = with_patch(a, (40, 40, 60, 60), (255, 255, 255, 255))
        b = solid((120, 120), (10, 10, 10, 255))
        b = with_patch(b, (42, 40, 62, 60), (255, 255, 255, 255))
        result = compare_renders.compare_images(a, b)
        self.assertTrue(result.passed)

    def test_large_shift_fails(self):
        a = solid((120, 120), (10, 10, 10, 255))
        a = with_patch(a, (40, 40, 60, 60), (255, 255, 255, 255))
        b = solid((120, 120), (10, 10, 10, 255))
        b = with_patch(b, (60, 40, 80, 60), (255, 255, 255, 255))
        result = compare_renders.compare_images(a, b)
        self.assertFalse(result.passed)

    def test_large_connected_block_fails(self):
        a = solid((100, 100), (10, 10, 10, 255))
        b = with_patch(a, (0, 0, 60, 60), (255, 255, 255, 255))
        result = compare_renders.compare_images(a, b)
        self.assertFalse(result.passed)

    def test_alpha_only_difference_is_detected(self):
        a = Image.new("RGBA", (40, 40), (10, 10, 10, 255))
        b = Image.new("RGBA", (40, 40), (10, 10, 10, 0))
        result = compare_renders.compare_images(a, b)
        self.assertFalse(result.passed)

    def test_size_mismatch_within_tolerance_is_padded_and_passes(self):
        a = solid((100, 100), (10, 10, 10, 255))
        b = solid((94, 100), (10, 10, 10, 255))
        result = compare_renders.compare_images(a, b)
        self.assertFalse(result.size_mismatch)
        self.assertTrue(result.passed)

    def test_size_mismatch_beyond_tolerance_fails(self):
        a = solid((100, 100), (10, 10, 10, 255))
        b = solid((40, 40), (10, 10, 10, 255))
        result = compare_renders.compare_images(a, b)
        self.assertTrue(result.size_mismatch)
        self.assertFalse(result.passed)

    def test_size_mismatch_reports_failure_without_exception(self):
        a = solid((40, 40), (10, 10, 10, 255))
        b = solid((80, 40), (10, 10, 10, 255))
        result = compare_renders.compare(Path("a.png"), Path("b.png"), None, a_image=a, b_image=b)
        self.assertFalse(result.passed)

    def test_same_absolute_area_change_judged_equally_on_small_and_large_images(self):
        small_a = solid((100, 100), (10, 10, 10, 255))
        small_b = with_patch(small_a, (10, 10, 34, 34), (255, 255, 255, 255))
        large_a = solid((2000, 1000), (10, 10, 10, 255))
        large_b = with_patch(large_a, (10, 10, 34, 34), (255, 255, 255, 255))
        small_result = compare_renders.compare_images(small_a, small_b)
        large_result = compare_renders.compare_images(large_a, large_b)
        self.assertTrue(small_result.passed)
        self.assertTrue(large_result.passed)

        small_b = with_patch(small_a, (10, 10, 70, 70), (255, 255, 255, 255))
        large_b = with_patch(large_a, (10, 10, 70, 70), (255, 255, 255, 255))
        small_result = compare_renders.compare_images(small_a, small_b)
        large_result = compare_renders.compare_images(large_a, large_b)
        self.assertFalse(small_result.passed)
        self.assertFalse(large_result.passed)

    def test_side_by_side_image_written_on_failure(self):
        import tempfile
        with tempfile.TemporaryDirectory() as before, tempfile.TemporaryDirectory() as after, \
                tempfile.TemporaryDirectory() as diff:
            before_path, after_path, diff_path = Path(before), Path(after), Path(diff)
            a = solid((100, 100), (10, 10, 10, 255))
            b = with_patch(a, (0, 0, 60, 60), (255, 255, 255, 255))
            a.save(before_path / "case.png")
            b.save(after_path / "case.png")
            exit_code = compare_renders.main([str(before_path), str(after_path), str(diff_path)])
            self.assertEqual(exit_code, 1)
            self.assertTrue((diff_path / "case.png").exists())
            self.assertTrue((diff_path / "case-side-by-side.png").exists())

    def test_extra_file_without_reference_reported_per_pair(self):
        import tempfile
        with tempfile.TemporaryDirectory() as before, tempfile.TemporaryDirectory() as after:
            before_path, after_path = Path(before), Path(after)
            solid((10, 10), (0, 0, 0, 255)).save(before_path / "both.png")
            solid((10, 10), (0, 0, 0, 255)).save(after_path / "both.png")
            solid((10, 10), (0, 0, 0, 255)).save(after_path / "only-after.png")
            exit_code = compare_renders.main([str(before_path), str(after_path)])
            self.assertEqual(exit_code, 1)

    def test_missing_file_reported_per_pair(self):
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
