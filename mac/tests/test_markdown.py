import unittest

from markdown import join_display_math, normalize, plain_title, tex_delimiters


class MarkdownTests(unittest.TestCase):
    def test_formula_inside_a_sentence_stays_in_its_paragraph(self):
        text = "a parameterized function\n\n$$\nf(x;\\theta), \\quad (0.1)\n$$\n\nwhere x is the input.\n\nNext paragraph."
        self.assertEqual(
            join_display_math(text),
            "a parameterized function\n$$\nf(x;\\theta), \\quad (0.1)\n$$\nwhere x is the input.\n\nNext paragraph.",
        )

    def test_formula_after_a_finished_sentence_stays_apart(self):
        text = "The sentence ends.\n\n$$a=b$$\n\nAnother paragraph."
        self.assertEqual(join_display_math(text), text)

    def test_tex_delimiters_become_dollars_outside_code(self):
        self.assertEqual(
            tex_delimiters("uses \\(x^2\\) and \\[y\\] but `\\(code\\)`"),
            "uses $x^2$ and $$y$$ but `\\(code\\)`",
        )

    def test_existing_math_and_latex_line_breaks_stay(self):
        text = "$$a \\\\[4pt] b$$ and $\\left(x\\right)$ stay"
        self.assertEqual(tex_delimiters(text), text)

    def test_title_keeps_link_text_only(self):
        self.assertEqual(plain_title("[vfxblog](https://vfxblog.com) **news**"), "vfxblog news")

    def test_normalize_leaves_plain_prose_alone(self):
        text = "# Title\n\nOne paragraph.\n\nTwo paragraph."
        self.assertEqual(normalize(text), text)


if __name__ == "__main__":
    unittest.main()
