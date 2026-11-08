import py_compile
import unittest
from pathlib import Path


class CompileTests(unittest.TestCase):
    def test_every_script_compiles(self):
        for path in sorted(Path(__file__).parent.glob("*.py")):
            with self.subTest(path=path.name):
                py_compile.compile(str(path), doraise=True)
