"""Export opt-in telemetry even after XCTest shuts down its simulator clone."""
import json
from pathlib import Path
import plistlib
import shutil

BUNDLE_ID = "us.naqshbaniaowaisiah"


def export(devices: Path, destination: Path, since: float = 0) -> list[str]:
    destination.mkdir(parents=True, exist_ok=True)
    copied = []
    base = "*/data/Containers/Data/Application/*/Documents/"
    sources = list(devices.glob(base + "audio-follow-audit.jsonl"))
    sources += list(devices.glob(base + "reader-audit-*.jsonl"))
    for source in sources:
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
        prefix = "audio-follow" if source.name == "audio-follow-audit.jsonl" else source.stem
        name = f"{prefix}-{device_id}-{container.name}.jsonl"
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
