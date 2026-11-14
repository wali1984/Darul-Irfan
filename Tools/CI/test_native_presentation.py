import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("native_presentation", Path(__file__).resolve().parents[1] / "validate_native_presentation.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class NativePresentationTests(unittest.TestCase):
    def test_reporting_channel_names_are_allowed_only_as_labels(self):
        for value in gate.ADMIN_CHANNEL_LABELS:
            failures = []
            gate.check("reporting label", value, failures, admin_channel_label=True)
            self.assertEqual(failures, [])
            gate.check("reader copy", value, failures)
            self.assertEqual(len(failures), 1)

    def test_label_exception_does_not_allow_a_content_handoff(self):
        for value in ["Open on website", "Read full version", "View source", "Read on naqshbandiaowaisiah.org"]:
            failures = []
            gate.check("changed reporting translation", value, failures, admin_channel_label=True)
            self.assertEqual(len(failures), 1)


if __name__ == "__main__":
    unittest.main()
