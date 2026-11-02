import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest

from sample_reader_process import new_reader_load
from export_audio_follow_diagnostics import export


class ReaderStartupDiagnosticsTests(unittest.TestCase):
    def fixture(self, root, name, bundle="us.naqshbaniaowaisiah", timestamp=100, focus=142):
        container = root / "device/data/Containers/Data/Application" / name
        documents = container / "Documents"
        documents.mkdir(parents=True)
        with (container / ".com.apple.mobile_container_manager.metadata.plist").open("wb") as stream:
            plistlib.dump({"MCMMetadataIdentifier": bundle}, stream)
        source = documents / "reader-audit-2-142-session.jsonl"
        source.write_text(json.dumps({"timestamp": timestamp, "requestedAyah": focus}) + "\n")
        os.utime(source, (timestamp, timestamp))
        return documents

    def test_only_current_app_and_current_run_trigger_startup_sample(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root, "wrong-app", bundle="other.app")
            self.fixture(root, "stale", timestamp=10)
            self.fixture(root, "wrong-target", focus=253)
            self.assertFalse(new_reader_load(root, since=50))
            self.fixture(root, "current")
            self.assertTrue(new_reader_load(root, since=50))

    def test_reopening_same_surah_exports_both_landings(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            documents = self.fixture(root, "current")
            second = documents / "reader-audit-2-253-second.jsonl"
            second.write_text('{"timestamp":110,"requestedAyah":253}\n')
            names = export(root, root / "output", since=50)
            self.assertEqual(len(names), 2)
            requests = {json.loads((root / "output" / name).read_text())["requestedAyah"] for name in names}
            self.assertEqual(requests, {142, 253})


if __name__ == "__main__":
    unittest.main()
