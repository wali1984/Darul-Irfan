import json
import ingest


def test_revision_changes_only_when_payload_changes(tmp_path):
    ingest.write_json(tmp_path/'articles.json', [])
    ingest._write_manifest(tmp_path, '2026-10-01T00:00:00Z')
    first=json.loads((tmp_path/'content_manifest.json').read_text())
    assert first['version'] == 1
    ingest._write_manifest(tmp_path, '2026-10-02T00:00:00Z')
    assert json.loads((tmp_path/'content_manifest.json').read_text()) == first
    ingest.write_json(tmp_path/'articles.json', [{'id':'exact-source-record'}])
    ingest._write_manifest(tmp_path, '2026-10-02T00:00:00Z')
    changed=json.loads((tmp_path/'content_manifest.json').read_text())
    assert changed['version'] == 2
    assert changed['contentHash'] != first['contentHash']


def test_existing_installed_version_is_superseded(tmp_path):
    ingest.write_json(tmp_path/'content_manifest.json', {'version':1})
    ingest._write_manifest(tmp_path, '2026-10-02T00:00:00Z')
    assert json.loads((tmp_path/'content_manifest.json').read_text())['version'] == 2
