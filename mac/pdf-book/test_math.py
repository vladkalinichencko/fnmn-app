import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("export_app_book", Path(__file__).with_name("export-app-book.py"))
export_app_book = importlib.util.module_from_spec(spec)
spec.loader.exec_module(export_app_book)
math_delimiter_errors = export_app_book.math_delimiter_errors


class MathDelimiterTests(unittest.TestCase):
    def test_balanced_environment_is_accepted(self):
        text = r"\[\begin{aligned}a &= \left(b\right)\end{aligned}\]"
        self.assertEqual(math_delimiter_errors(text), [])

    def test_unclosed_group_names_its_line(self):
        text = "ok\n" + r"\[\begin{aligned}\frac{1}{2\end{aligned}\]"
        self.assertEqual(math_delimiter_errors(text), ["math_delimiters:2"])

    def test_left_without_right_is_rejected(self):
        text = r"\[\begin{cases}1 & \left(x\end{cases}\]"
        self.assertEqual(math_delimiter_errors(text), ["math_delimiters:1"])


if __name__ == "__main__":
    unittest.main()
