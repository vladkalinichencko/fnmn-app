import unittest

from markdown import bold_runs, had_site_header, headings, join_display_math, material_title, normalize, plain_title, tex_delimiters, without_page_chrome


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

    def test_dollars_inside_brackets_do_not_end_the_formula(self):
        self.assertEqual(
            tex_delimiters("\\[\\begin{split} a &= b \\text{ for $x$} \\end{split}\\] then $y$ and \\(z \\text{ of $w$}\\)"),
            "$$\\begin{split} a &= b \\text{ for x} \\end{split}$$ then $y$ and $z \\text{ of w}$",
        )

    def test_existing_math_and_latex_line_breaks_stay(self):
        text = "$$a \\\\[4pt] b$$ and $\\left(x\\right)$ stay"
        self.assertEqual(tex_delimiters(text), text)

    def test_title_keeps_link_text_only(self):
        self.assertEqual(plain_title("[vfxblog](https://vfxblog.com) **news**"), "vfxblog news")

    def test_title_keeps_a_linked_images_alt_text_only(self):
        self.assertEqual(plain_title("[![Rehaan Ahmad](img.png)](https://alphaxiv.org/@rehaan-ahmad)"), "Rehaan Ahmad")

    def test_site_header_and_byline_are_not_the_article(self):
        text = "# [vfxblog](https://vfxblog.com)\n\n# Heads up: the oral history\n\n*By Ian Failes*\n\nIt’s ten years since."
        self.assertEqual(without_page_chrome(text), "# Heads up: the oral history\n\nIt’s ten years since.")
        self.assertTrue(had_site_header(text))
        self.assertFalse(had_site_header("# Heads up\n\nText"))

    def test_bold_runs_from_html_read_as_bold(self):
        self.assertEqual(bold_runs("**Eyes:**green"), "**Eyes:** green")
        self.assertEqual(bold_runs("**—****Why?**"), "**— Why?**")
        self.assertEqual(bold_runs("**«****Prophet****»****ended**"), "**«Prophet» ended**")
        self.assertEqual(bold_runs("[Alena](https://a.b)**did not**"), "[Alena](https://a.b) **did not**")
        self.assertEqual(bold_runs("[film](https://a.b)**, but**"), "[film](https://a.b)**, but**")
        self.assertEqual(bold_runs("a** **b and **world****with** it"), "a b and **world with** it")
        self.assertEqual(bold_runs("Search ** [2] rewards **all** of it"), "Search ** [2] rewards **all** of it")
        self.assertEqual(bold_runs("`a**b` and $x**2$ **stay**."), "`a**b` and $x**2$ **stay**.")
        self.assertEqual(bold_runs('"**Quoted**" and **tanh**-like, **vol**umetric pi**xel**'), '"**Quoted**" and **tanh**-like, **vol**umetric pi**xel**')
        self.assertEqual(bold_runs("proposed****MaskLLM****—"), "proposed****MaskLLM****—")
        self.assertEqual(bold_runs("- ****Nested****(****h****)"), "- ****Nested****(****h****)")

    def test_heading_loses_bold_and_a_paragraph_long_one_is_a_paragraph(self):
        self.assertEqual(headings("## **Short** **one**"), "## Short one")
        lead = "Word " * 60
        self.assertEqual(headings(f"#### **{lead}**"), lead.strip())

    def test_code_keeps_its_hashes_and_stars(self):
        text = "```\n# **not a heading**\na****b\n```"
        self.assertEqual(normalize(text), text)

    def test_horizontal_rules_go_but_a_heading_underline_and_code_stay(self):
        self.assertEqual(normalize("One.\n\n---\n\nTwo.\n\n* * *\n\nThree."), "One.\n\nTwo.\n\nThree.")
        self.assertEqual(normalize("Title\n---\n\nText."), "Title\n---\n\nText.")
        self.assertEqual(normalize("```\n---\n```"), "```\n---\n```")

    def test_normalize_leaves_plain_prose_alone(self):
        text = "# Title\n\nOne paragraph.\n\nTwo paragraph."
        self.assertEqual(normalize(text), text)


class MaterialTitleTests(unittest.TestCase):
    def test_the_page_title_wins_and_loses_the_site(self):
        self.assertEqual(material_title("Momentum – vfxblog", "# Another\n\nText", "example.com"), "Momentum")

    def test_without_a_page_title_the_first_heading_names_it(self):
        self.assertEqual(material_title(None, "# Momentum\n\nText", "example.com"), "Momentum")

    def test_a_page_title_of_spaces_falls_through(self):
        self.assertEqual(material_title("   ", "# Momentum\n\nText", "example.com"), "Momentum")

    def test_without_either_the_address_names_it(self):
        self.assertEqual(material_title(None, "Text only", "example.com"), "example.com")


if __name__ == "__main__":
    unittest.main()
