import os
from pathlib import Path
import plistlib
import tempfile
import unittest

from export_audio_follow_diagnostics import BUNDLE_ID, export


class ExportTelemetryTests(unittest.TestCase):
    def test_shutdown_clone_files_export_without_simctl_or_booted_device(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for device in ("original", "test-clone"):
                container = root / device / "data/Containers/Data/Application/app-container"
                (container / "Documents").mkdir(parents=True)
                (container / "Documents/audio-follow-audit.jsonl").write_text('{"seconds":42}\n')
                with (container / ".com.apple.mobile_container_manager.metadata.plist").open("wb") as stream:
                    plistlib.dump({"MCMMetadataIdentifier": BUNDLE_ID}, stream)
            result = export(root, root / "output")
            self.assertEqual(len(result), 2)
            self.assertNotEqual(result[0], result[1])
            for name in result:
                self.assertEqual((root / "output" / name).read_text(), '{"seconds":42}\n')

    def test_wrong_app_stale_and_empty_files_are_excluded(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("wrong-app", "stale", "empty", "current"):
                container = root / "device/data/Containers/Data/Application" / name
                (container / "Documents").mkdir(parents=True)
                source = container / "Documents/audio-follow-audit.jsonl"
                source.write_text('' if name == "empty" else '{"seconds":1}\n')
                os.utime(source, (10 if name == "stale" else 100,) * 2)
                with (container / ".com.apple.mobile_container_manager.metadata.plist").open("wb") as stream:
                    plistlib.dump({"MCMMetadataIdentifier": "another.app" if name == "wrong-app" else BUNDLE_ID}, stream)
            self.assertEqual(export(root, root / "output", since=50), ["audio-follow-device-current.jsonl"])


if __name__ == "__main__":
    unittest.main()
