import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

import ocr_jobs


class EmptyRunTests(unittest.TestCase):
    def test_no_jobs_writes_the_overrides_and_never_loads_the_model(self):
        with TemporaryDirectory() as folder:
            output = Path(folder) / "out.json"
            ocr_jobs.run(
                [],
                candidates=Path(folder) / "candidates.json",
                output=output,
                raw=Path(folder),
                overrides={"1:2": "kept"},
                model_name="a-model-that-is-not-installed",
                label="Test",
                unit="job",
                key=lambda issue: issue["n"],
                select=lambda page, issue, text: text,
                metrics=lambda issue, result, seconds, value: {},
            )
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), {"1:2": "kept"})
