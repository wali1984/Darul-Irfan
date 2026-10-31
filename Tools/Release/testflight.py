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
(TestFlight has no lookup an app can ask). The R2 credentials are the "S3
clients" ones in `cloudflare.md` one folder above this repository (outside
git), never printed.
"""
from __future__ import annotations

import json
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import jwt  # PyJWT

REPO = Path(__file__).resolve().parents[2]
CONFIG = REPO.parent / "appstoreconnect.md"
API = "https://api.appstoreconnect.apple.com"
APP = "6789375037"
EXTERNAL_GROUP = "040ba83d-04ce-4f69-8ed0-7a838d64bdc1"
R2_CONFIG = REPO.parent / "cloudflare.md"
BUCKET, RELEASES = "darul-irfan-media", "app/releases.json"
POLICY = REPO.parent / "automation" / "testflight-policy.json"


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


def token() -> str:
    issuer, kid = credentials()
    key = (REPO / f"AuthKey_{kid}.p8").read_text(encoding="utf-8")
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
    status, body = call("GET", path)
    if status >= 300 or not isinstance(body, dict):
        raise RuntimeError(f"GET {path}: HTTP {status} {body}")
    return body


def newest(count: int = 5) -> list[dict]:
    """The newest builds of the app: number, upload time, processing state."""
    data = get(f"/v1/builds?filter[app]={APP}&sort=-uploadedDate&limit={count}"
               "&fields[builds]=version,uploadedDate,processingState").get("data", [])
    return [{"number": b["attributes"]["version"], "uploaded": b["attributes"]["uploadedDate"],
             "state": b["attributes"]["processingState"]} for b in data]


def release(number: str, notes: str) -> int:
    policy = distribution_policy()
    if not policy.get("externalDistributionEnabled", False) or int(number) > int(policy.get("externalBuildCeiling", 70)):
        print("External distribution held by owner policy; internal uploads are unaffected.")
        return 1
    build = None
    for _ in range(120):
        found = get(f"/v1/builds?filter[app]={APP}&filter[version]={number}&fields[builds]=version,processingState").get("data", [])
        if found and found[0]["attributes"]["processingState"] == "VALID":
            build = found[0]
            break
        print(f"build {number}: {found[0]['attributes']['processingState'] if found else 'not uploaded yet'}", flush=True)
        time.sleep(60)
    if build is None:
        print("gave up waiting for processing")
        return 1
    build_id = build["id"]

    # Export compliance: standard HTTPS only.
    call("PATCH", f"/v1/builds/{build_id}", {"data": {"type": "builds", "id": build_id,
                                                      "attributes": {"usesNonExemptEncryption": False}}})
    localizations = get(f"/v1/builds/{build_id}/betaBuildLocalizations").get("data", [])
    if localizations:
        status, _ = call("PATCH", f"/v1/betaBuildLocalizations/{localizations[0]['id']}",
                         {"data": {"type": "betaBuildLocalizations", "id": localizations[0]["id"],
                                   "attributes": {"whatsNew": notes}}})
    else:
        status, _ = call("POST", "/v1/betaBuildLocalizations",
                         {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": notes},
                                   "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    print("what to test:", status)
    status, body = call("POST", f"/v1/betaGroups/{EXTERNAL_GROUP}/relationships/builds",
                        {"data": [{"type": "builds", "id": build_id}]})
    print("added to external group:", status, "" if status < 300 else body)
    status, body = call("POST", "/v1/betaAppReviewSubmissions",
                        {"data": {"type": "betaAppReviewSubmissions",
                                  "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    # 409 when this build was already submitted: not an error for a re-run.
    print("submitted for beta review:", status, "" if status < 300 or status == 409 else body)
    detail = get(f"/v1/builds/{build_id}/buildBetaDetail").get("data", {}).get("attributes", {})
    print("external state:", detail.get("externalBuildState"))
    return 0


def tester_build() -> tuple[int, str] | None:
    """(build number, version) of the newest build Apple has passed for the
    external testers."""
    data = get(f"/v1/builds?filter[app]={APP}&sort=-uploadedDate&limit=20&include=preReleaseVersion,buildBetaDetail"
               "&fields[builds]=version,preReleaseVersion,buildBetaDetail&fields[preReleaseVersions]=version"
               "&fields[buildBetaDetails]=externalBuildState")
    included = {(item["type"], item["id"]): item["attributes"] for item in data.get("included", [])}
    passed = []
    for build in data.get("data", []):
        links = build["relationships"]
        detail = included.get(("buildBetaDetails", links["buildBetaDetail"]["data"]["id"]), {})
        if detail.get("externalBuildState") == "IN_BETA_TESTING":
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


def announce(known: int | None = None) -> int | None:
    """Name the newest tester build in app/releases.json. Returns its number
    when the file changed; nothing is read from R2 while it is `known`."""
    found = tester_build()
    if not found or found[0] == known:
        return None
    number, version = found
    if number > int(distribution_policy().get("externalBuildCeiling", 70)):
        print("External update announcement held by owner policy.")
        return None
    bucket = r2()
    try:
        releases = json.loads(bucket.get_object(Bucket=BUCKET, Key=RELEASES)["Body"].read())
    except bucket.exceptions.NoSuchKey:
        releases = {}
    if releases.get("ios", {}).get("testflight", {}).get("build") == number:
        return None
    releases.setdefault("ios", {})["testflight"] = {
        "version": version, "build": number,
        "releasedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    bucket.put_object(Bucket=BUCKET, Key=RELEASES, Body=json.dumps(releases, separators=(",", ":")).encode(),
                      ContentType="application/json", CacheControl="public, max-age=300")
    return number


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
        print(f"announced build {number}" if number else "already announced")
        return 0
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main())
