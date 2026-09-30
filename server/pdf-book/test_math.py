import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("export_app_book", Path(__file__).with_name("export-app-book.py"))
export_app_book = importlib.util.module_from_spec(spec)
spec.loader.exec_module(export_app_book)
math_delimiter_errors = export_app_book.math_delimiter_errors

math_spec = importlib.util.spec_from_file_location("math_issues", Path(__file__).with_name("math_issues.py"))
math_issues_module = importlib.util.module_from_spec(math_spec)
math_spec.loader.exec_module(math_issues_module)
select_formula = math_issues_module.select_formula
formula_jobs = math_issues_module.formula_jobs


class MathDelimiterTests(unittest.TestCase):
    def test_balanced_environment_is_accepted(self):
        text = r"\[\begin{aligned}a &= \left(b\right)\end{aligned}\]"
        self.assertEqual(math_delimiter_errors(text), [])

    def test_escaped_braces_are_not_groups(self):
        text = r"\[\frac{\{1\}}{2}\]"
        self.assertEqual(math_delimiter_errors(text), [])

    def test_unclosed_group_names_its_line(self):
        text = "ok\n" + r"\[\begin{aligned}\frac{1}{2\end{aligned}\]"
        self.assertEqual(math_delimiter_errors(text), ["unbalanced_group:2"])

    def test_left_without_right_is_rejected(self):
        text = r"\[\begin{cases}1 & \left(x\end{cases}\]"
        self.assertEqual(math_delimiter_errors(text), ["unbalanced_left_right:1"])

    def test_one_balanced_region_is_kept(self):
        text = "<|ref|>equation<|/ref|><|det|>[[0, 0, 1, 1]]<|/det|>\n$$a = b$$"
        self.assertEqual(select_formula(text), "$$a = b$$")

    def test_unbalanced_region_is_refused(self):
        self.assertIsNone(select_formula(r"$$\frac{1}{2$$"))

    def test_two_regions_are_refused(self):
        self.assertIsNone(select_formula("$$a$$ $$b$$"))

    def test_formula_job_uses_one_crop_per_equation(self):
        candidates = [{'page': 4, 'issues': [
            {'type': 'unbalanced_group', 'equation': 2, 'image': 'assets/page-4-formula-2.png'},
            {'type': 'unbalanced_left_right', 'equation': 2, 'image': 'assets/page-4-formula-2.png'},
            {'type': 'footnote_needs_ocr', 'number': 1, 'image': 'assets/note.png'},
            {'type': 'unbalanced_group', 'line': 3, 'formula': r'$\frac{1}{2$'},
        ]}]
        self.assertEqual(formula_jobs(candidates), [
            (4, {'type': 'unbalanced_group', 'equation': 2, 'image': 'assets/page-4-formula-2.png'}),
        ])


if __name__ == "__main__":
    unittest.main()
