import unittest

from grounding import blocks, strip


class StripTests(unittest.TestCase):
    def test_text_without_markers_is_returned_trimmed(self):
        self.assertEqual(strip("  plain text \n"), "plain text")

    def test_each_region_keeps_its_text_and_the_markers_go(self):
        text = (
            "<|ref|>footnote<|/ref|><|det|>[[1, 2, 3, 4]]<|/det|>\nOne\n"
            "<|ref|>footnote<|/ref|><|det|>[[5, 6, 7, 8]]<|/det|>\nTwo"
        )
        self.assertEqual(strip(text), "One\n\nTwo")

    def test_a_markers_only_page_strips_to_nothing(self):
        self.assertEqual(strip("<|ref|>x<|/ref|><|det|>[[0, 0, 1, 1]]<|/det|>\n"), "")


class BlockTests(unittest.TestCase):
    def test_a_region_keeps_its_kind_its_box_and_its_text(self):
        text = '<|ref|>text<|/ref|><|det|>[[1, 2, 3, 4]]<|/det|>\nHello'
        self.assertEqual(blocks(text), [{"kind": "text", "bbox": [1, 2, 3, 4], "text": "Hello"}])

    def test_text_outside_the_regions_is_refused(self):
        text = 'stray\n<|ref|>text<|/ref|><|det|>[[1, 2, 3, 4]]<|/det|>\nHello'
        with self.assertRaises(ValueError):
            blocks(text)

    def test_an_empty_page_has_no_blocks(self):
        self.assertEqual(blocks(""), [])
