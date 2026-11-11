"""App Store Connect from this PC: list builds, and put a TestFlight build in
front of the testers.

The API key is AuthKey_<KEY>.p8 in this repository's root (git-ignored); the
issuer and key ids are in `appstoreconnect.md` one folder above this repository
(outside git, lines "ISSUER: <id>" and "KEY: <id>"). Neither is ever printed.

usage:
  testflight.py newest [count]                 newest builds and their processing state
  testflight.py release <build number> "<what to test>"
  testflight.py announce                       name the newest tester build to the apps

`release` waits until App Store Connect has processed the build, sets its What
to Test text, adds it to the external group and submits it for Beta App Review.
If an earlier build of the same version is already approved, Apple usually
passes this one without a full review and the testers are notified straight
away; if the earlier build is still waiting, this one joins the queue.

`announce` writes the newest build Apple has passed for the external testers
to app/releases.json in R2, which the server serves at /v1/app/releases: a
TestFlight copy on an older build then shows the update banner on Today
(TestFlight has no lookup an app can ask). It also writes the newest build the
internal testers have ("internal"), which only a copy already on a build later
than the external one offers, so internal-only releases show the banner to the
internal testers and never to the external ones. The R2 credentials are the "S3
clients" ones in `cloudflare.md` one folder above this repository (outside
git), never printed.
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import jwt  # PyJWT

REPO = Path(__file__).resolve().parents[2]


def shared_root(repo: Path) -> Path:
    """Support both the original checkout and a checkout under pw/."""
    for candidate in (repo.parent, repo.parent.parent):
        if (candidate / "appstoreconnect.md").is_file():
            return candidate
    return repo.parent


SHARED_ROOT = shared_root(REPO)
CONFIG = SHARED_ROOT / "appstoreconnect.md"
API = "https://api.appstoreconnect.apple.com"
APP = "6789375037"
EXTERNAL_GROUP = "040ba83d-04ce-4f69-8ed0-7a838d64bdc1"
INTERNAL_GROUP = "bbdefdf1-8727-465a-b7e2-1817ea45cbb8"
R2_CONFIG = SHARED_ROOT / "cloudflare.md"
BUCKET, RELEASES = "darul-irfan-media", "app/releases.json"
POLICY = SHARED_ROOT / "automation" / "testflight-policy.json"


def distribution_policy() -> dict:
    """Keep unattended release jobs within the owner's explicit tester scope."""
    if POLICY.exists():
        return json.loads(POLICY.read_text(encoding="utf-8"))
    return {"externalDistributionEnabled": False, "externalBuildCeiling": 70}


def credentials() -> tuple[str, str]:
    if not CONFIG.exists():
        sys.exit(f"No App Store Connect settings: add 'ISSUER: <id>' and 'KEY: <id>' to {CONFIG}")
    text = CONFIG.read_text(encoding="utf-8")
    issuer = re.search(r"ISSUER:\s*(\S+)", text); key = re.search(r"KEY:\s*(\S+)", text)
    if not issuer or not key:
        sys.exit(f"{CONFIG} needs lines 'ISSUER: <id>' and 'KEY: <id>'")
    return issuer.group(1), key.group(1)


def private_key_file(kid: str) -> Path:
    """Read existing ignored keys; never copy them into a worktree."""
    explicit = os.environ.get("DARUL_IRFAN_ASC_KEY_FILE")
    candidates = [Path(explicit)] if explicit else [REPO / f"AuthKey_{kid}.p8", SHARED_ROOT / "DarulIrfan-iOS" / f"AuthKey_{kid}.p8"]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise FileNotFoundError("App Store Connect key missing; set DARUL_IRFAN_ASC_KEY_FILE to its existing location")


def token() -> str:
    issuer, kid = credentials()
    key = private_key_file(kid).read_text(encoding="utf-8")
    now = int(time.time())
    return jwt.encode({"iss": issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})


def call(method: str, path: str, body: dict | None = None) -> tuple[int, dict | str]:
    request = urllib.request.Request(API + path, data=json.dumps(body).encode() if body else None, method=method,
                                     headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
                return response.status, json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            return error.code, error.read().decode(errors="replace")[:400]
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == 4:
                raise
            time.sleep(10 * (attempt + 1))
    raise RuntimeError("unreachable")


def get(path: str) -> dict:
    if path.startswith(API + "/"):
        path = path[len(API):]
    if not path.startswith("/") or path.startswith("//"):
        raise ValueError("App Store Connect path required")
    status, body = call("GET", path)
    if status >= 300 or not isinstance(body, dict):
        raise RuntimeError(f"GET {path}: HTTP {status} {body}")
    return body


def checked_call(method: str, path: str, body: dict) -> dict | str:
    status, result = call(method, path, body)
    if not 200 <= status < 300:
        raise RuntimeError(f"{method} {path}: HTTP {status} {result}")
    return result


def group_build_ids(group_id: str) -> set[str]:
    ids: set[str] = set()
    path = f"/v1/betaGroups/{group_id}/relationships/builds?limit=200"
    visited: set[str] = set()
    while path:
        if path in visited:
            raise RuntimeError("Repeated TestFlight group pagination link")
        visited.add(path)
        page = get(path)
        ids.update(item["id"] for item in page.get("data", []))
        path = page.get("links", {}).get("next")
    return ids


def distribution_status(build_id: str) -> dict:
    build = get(f"/v1/builds/{build_id}?fields[builds]=version,processingState,expired")["data"]["attributes"]
    detail = get(f"/v1/builds/{build_id}/buildBetaDetail")["data"]["attributes"]
    valid = build.get("processingState") == "VALID" and not build.get("expired", False)
    internal_group = build_id in group_build_ids(INTERNAL_GROUP)
    external_group = build_id in group_build_ids(EXTERNAL_GROUP)
    return {"build": build.get("version"), "processingState": build.get("processingState"),
            "internalGroupAssigned": internal_group, "externalGroupAssigned": external_group,
            "internalBuildState": detail.get("internalBuildState"), "externalBuildState": detail.get("externalBuildState"),
            "internalAvailable": valid and internal_group and detail.get("internalBuildState") == "IN_BETA_TESTING",
            "externalAvailable": valid and external_group and detail.get("externalBuildState") == "IN_BETA_TESTING"}


def newest(count: int = 5) -> list[dict]:
    """The newest builds of the app: number, upload time, processing state."""
    data = get(f"/v1/builds?filter[app]={APP}&sort=-uploadedDate&limit={count}"
               "&fields[builds]=version,uploadedDate,processingState").get("data", [])
    return [{"number": b["attributes"]["version"], "uploaded": b["attributes"]["uploadedDate"],
             "state": b["attributes"]["processingState"]} for b in data]


def release(number: str, notes: str) -> int:
    if not number.isdigit() or int(number) < 1 or not notes.strip() or len(notes) > 4000:
        raise ValueError("A positive build number and 1–4000 characters of release notes are required")
    policy = distribution_policy()
    if (not policy.get("externalDistributionEnabled", False)
            or int(number) > int(policy.get("externalBuildCeiling", 70))
            or int(number) > int(policy.get("internalBuild", 70))):
        print("External distribution held by owner policy; internal uploads are unaffected.")
        return 1
    build = None
    for _ in range(120):
        found = get(f"/v1/builds?filter[app]={APP}&filter[version]={number}&fields[builds]=version,processingState").get("data", [])
        if found and found[0]["attributes"]["processingState"] == "VALID":
            build = found[0]
            break
        if found and found[0]["attributes"]["processingState"] in {"FAILED", "INVALID"}:
            raise RuntimeError(f"Build {number} failed Apple processing")
        print(f"build {number}: {found[0]['attributes']['processingState'] if found else 'not uploaded yet'}", flush=True)
        time.sleep(60)
    if build is None:
        print("gave up waiting for processing")
        return 1
    build_id = build["id"]

    # Export compliance: standard HTTPS only. Apple refuses to change it once
    # it is set (the Info.plist's ITSAppUsesNonExemptEncryption sets it at
    # upload), so a value already false is fine.
    compliance = get(f"/v1/builds/{build_id}?fields[builds]=usesNonExemptEncryption")["data"]["attributes"]
    if compliance.get("usesNonExemptEncryption") is None:
        checked_call("PATCH", f"/v1/builds/{build_id}", {"data": {"type": "builds", "id": build_id,
                                                          "attributes": {"usesNonExemptEncryption": False}}})
    elif compliance["usesNonExemptEncryption"]:
        raise RuntimeError(f"Build {number} declares non-exempt encryption; not released")
    localizations = get(f"/v1/builds/{build_id}/betaBuildLocalizations").get("data", [])
    english = next((item for item in localizations if item.get("attributes", {}).get("locale") == "en-US"), None)
    if english:
        checked_call("PATCH", f"/v1/betaBuildLocalizations/{english['id']}",
                         {"data": {"type": "betaBuildLocalizations", "id": english["id"],
                                   "attributes": {"whatsNew": notes}}})
    else:
        checked_call("POST", "/v1/betaBuildLocalizations",
                         {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": notes},
                                   "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    for group in (INTERNAL_GROUP, EXTERNAL_GROUP):
        # A group with every build (the owner set TESTERS so, 2026-11-10)
        # gets each one by itself: Apple refuses an assignment to it.
        if get(f"/v1/betaGroups/{group}")["data"]["attributes"].get("hasAccessToAllBuilds"):
            continue
        if build_id not in group_build_ids(group):
            checked_call("POST", f"/v1/betaGroups/{group}/relationships/builds",
                         {"data": [{"type": "builds", "id": build_id}]})
    detail = get(f"/v1/builds/{build_id}/buildBetaDetail")["data"]
    if not detail["attributes"].get("autoNotifyEnabled"):
        checked_call("PATCH", f"/v1/buildBetaDetails/{detail['id']}",
                     {"data": {"type": "buildBetaDetails", "id": detail["id"], "attributes": {"autoNotifyEnabled": True}}})
    if detail["attributes"].get("externalBuildState") != "IN_BETA_TESTING":
        status, body = call("POST", "/v1/betaAppReviewSubmissions",
                        {"data": {"type": "betaAppReviewSubmissions",
                                  "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
        if status == 409:
            # A conflict can be invalid metadata, not merely a duplicate.
            submission = get(f"/v1/builds/{build_id}/betaAppReviewSubmission").get("data")
            if not submission or submission.get("attributes", {}).get("betaReviewState") not in {"WAITING_FOR_REVIEW", "IN_REVIEW", "APPROVED"}:
                raise RuntimeError(f"Beta submission conflict was not an accepted existing submission: {body}")
        elif not 200 <= status < 300:
            raise RuntimeError(f"Beta submission failed: HTTP {status} {body}")
    verified = distribution_status(build_id)
    print(json.dumps(verified, indent=2))
    if verified["internalAvailable"] and verified["externalAvailable"]:
        return 0
    print("Tester availability is still pending; no successful release is claimed.")
    return 1


def tester_build() -> tuple[int, str] | None:
    """(build number, version) of the newest build Apple has passed for the
    external testers."""
    assigned = group_build_ids(EXTERNAL_GROUP)
    data = get(f"/v1/builds?filter[app]={APP}&sort=-uploadedDate&limit=20&include=preReleaseVersion,buildBetaDetail"
               "&fields[builds]=version,processingState,expired,preReleaseVersion,buildBetaDetail&fields[preReleaseVersions]=version"
               "&fields[buildBetaDetails]=externalBuildState")
    included = {(item["type"], item["id"]): item["attributes"] for item in data.get("included", [])}
    passed = []
    for build in data.get("data", []):
        links = build["relationships"]
        detail = included.get(("buildBetaDetails", links["buildBetaDetail"]["data"]["id"]), {})
        if (build["id"] in assigned and build["attributes"].get("processingState") == "VALID"
                and not build["attributes"].get("expired", False) and detail.get("externalBuildState") == "IN_BETA_TESTING"):
            version = included.get(("preReleaseVersions", links["preReleaseVersion"]["data"]["id"]), {}).get("version")
            passed.append((int(build["attributes"]["version"]), version))
    return max(passed) if passed else None


def r2():
    """The media bucket, with the "credentials for S3 clients" in cloudflare.md."""
    import boto3
    lines = [line.strip() for line in R2_CONFIG.read_text(encoding="utf-8").splitlines()]

    def after(label: str) -> str:
        return next(line for line in lines[lines.index(label) + 1:] if line)

    endpoint = next(line for line in lines if line.startswith("https://") and ".r2.cloudflarestorage.com" in line)
    return boto3.client("s3", endpoint_url=endpoint, aws_access_key_id=after("Access Key ID"),
                        aws_secret_access_key=after("Secret Access Key"), region_name="auto")


def internal_build() -> tuple[int, str] | None:
    """Newest available build actually assigned to the internal tester group."""
    assigned = group_build_ids(INTERNAL_GROUP)
    data = get(f"/v1/builds?filter[app]={APP}&sort=-uploadedDate&limit=20&include=preReleaseVersion,buildBetaDetail"
               "&fields[builds]=version,processingState,expired,preReleaseVersion,buildBetaDetail&fields[preReleaseVersions]=version"
               "&fields[buildBetaDetails]=internalBuildState")
    included = {(item["type"], item["id"]): item["attributes"] for item in data.get("included", [])}
    ceiling = int(distribution_policy().get("internalBuild", 10**9))
    valid = []
    for build in data.get("data", []):
        number = int(build["attributes"]["version"])
        detail_link = build["relationships"].get("buildBetaDetail", {}).get("data") or {}
        detail = included.get(("buildBetaDetails", detail_link.get("id")), {})
        if (build["id"] in assigned and build["attributes"]["processingState"] == "VALID" and number <= ceiling
                and not build["attributes"].get("expired", False) and detail.get("internalBuildState") == "IN_BETA_TESTING"):
            link = build["relationships"]["preReleaseVersion"]["data"]["id"]
            valid.append((number, included.get(("preReleaseVersions", link), {}).get("version")))
    return max(valid) if valid else None


def announce(known: int | None = None) -> int | None:
    """Name the newest tester builds in app/releases.json: the external
    testers' (its number is returned when it changed) and the internal
    testers' newest. `known` is the external build last announced."""
    found = tester_build()
    if found and found[0] > int(distribution_policy().get("externalBuildCeiling", 70)):
        print("External update announcement held by owner policy.")
        found = None
    inside = internal_build()
    if not inside and (not found or found[0] == known):
        return None
    bucket = r2()
    try:
        releases = json.loads(bucket.get_object(Bucket=BUCKET, Key=RELEASES)["Body"].read())
    except bucket.exceptions.NoSuchKey:
        releases = {}
    ios = releases.setdefault("ios", {})
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    changed = None
    if found and ios.get("testflight", {}).get("build", 0) < found[0]:
        ios["testflight"] = {"version": found[1], "build": found[0], "releasedAt": now}
        changed = found[0]
    if inside and ios.get("internal", {}).get("build", 0) < inside[0]:
        ios["internal"] = {"version": inside[1], "build": inside[0], "releasedAt": now}
    elif changed is None:
        return None
    bucket.put_object(Bucket=BUCKET, Key=RELEASES, Body=json.dumps(releases, separators=(",", ":")).encode(),
                      ContentType="application/json", CacheControl="public, max-age=300")
    return changed


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    args = sys.argv[1:]
    if not args or args[0] == "newest":
        for build in newest(int(args[1]) if len(args) > 1 else 5):
            print(build["number"], build["uploaded"], build["state"])
        return 0
    if args[0] == "release" and len(args) == 3:
        return release(args[1], args[2])
    if args[0] == "announce":
        number = announce()
        print(f"announced build {number}" if number else "external build already announced")
        return 0
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main())
