"""Export opt-in telemetry even after XCTest shuts down its simulator clone."""
import json
from pathlib import Path
import plistlib
import shutil

BUNDLE_ID = "us.naqshbaniaowaisiah"


def export(devices: Path, destination: Path, since: float = 0) -> list[str]:
    destination.mkdir(parents=True, exist_ok=True)
    copied = []
    pattern = "*/data/Containers/Data/Application/*/Documents/audio-follow-audit.jsonl"
    for source in devices.glob(pattern):
        if source.stat().st_mtime < since or source.stat().st_size == 0:
            continue
        container = source.parent.parent
        metadata = container / ".com.apple.mobile_container_manager.metadata.plist"
        try:
            with metadata.open("rb") as stream:
                identifier = plistlib.load(stream).get("MCMMetadataIdentifier")
        except (OSError, ValueError, plistlib.InvalidFileException):
            continue
        if identifier != BUNDLE_ID:
            continue
        device_id = source.relative_to(devices).parts[0]
        name = f"audio-follow-{device_id}-{container.name}.jsonl"
        shutil.copyfile(source, destination / name)
        copied.append(name)
    return sorted(copied)


def main():
    marker = Path("build/audio-follow-started")
    since = marker.stat().st_mtime - 2 if marker.exists() else 0
    destination = Path("build/screens")
    copied = export(Path.home() / "Library/Developer/CoreSimulator/Devices", destination, since)
    result = {"files": copied, "captured": bool(copied), "currentRunMarker": marker.exists()}
    (destination / "audio-follow-export.json").write_text(json.dumps(result, indent=2))
    print("Playback telemetry export:", json.dumps(result))


if __name__ == "__main__":
    main()
