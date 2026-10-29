"""Release Akram-ut-Tafaseer once Claude's November re-read of it is finished.

On 1 November 2026 amd starts Claude's re-read of all 31 printed parts of
Akram-ut-Tafaseer (cron, /mnt/sata1tb/di-claude-ocr/claude_ocr_akram.py). The
owner asked for the result to reach the app by itself ("auto update tag
release"). Windows Task Scheduler runs this script every two hours from then
on (task "Darul Irfan - Akram-ut-Tafaseer release"). Each run does nothing
until amd reports the re-read finished, and nothing at all once the release is
done.

When the re-read is finished, the script:
  1. checks that the four platform repositories are on main, clean, and level
     with GitHub; otherwise it waits, because a person is working in them;
  2. copies Claude's pages from amd;
  3. puts them into the app's book pages, adding the pages the app lacks, such
     as Parah 30 part 2 (ingest_claude_pages.py --add-pages --write);
  4. re-keys the per-ayah Akram-ut-Tafaseer rows and the volume links
     (segment_akram_tafaseer.py --write);
  5. bumps the content manifest on all four platforms;
  6. runs the content checks and the web app's tests and build;
  7. commits and pushes the four repositories and tags the iOS one;
  8. deploys the web app and checks that it serves the new content;
  9. builds for TestFlight on Codemagic and puts the build in front of the
     testers. A build the tag push already started is used rather than a
     second one; while Codemagic refuses to build for billing (HTTP 402) the
     run only logs it once and tries again next time.

A failed step stops the run and logs the reason. Nothing is reset, stashed or
forced. Steps 1 to 7 change the working trees, so a failure there leaves them
for a person. Steps 8 and 9 are retried on the next run.

    python Tools/Release/akram_tafaseer_release.py status
    python Tools/Release/akram_tafaseer_release.py run
    python Tools/Release/akram_tafaseer_release.py dry-run [--pages <dir>]   every check, no change

Log and state: ../automation/akram-tafaseer/ (outside git).
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
IOS = HERE.parents[1]
ROOT = IOS.parent
sys.path.insert(0, str(HERE))
import codemagic  # noqa: E402
import testflight  # noqa: E402

WORK = ROOT / "automation" / "akram-tafaseer"
LOG, STATE, LOCK = WORK / "release.log", WORK / "state.json", WORK / "run.lock"
AMD = "wali@10.10.100.100"
AMD_RUN = "/mnt/sata1tb/di-claude-ocr/run_akram"
SSH = Path(r"C:\Program Files\Git\usr\bin\ssh.exe")
ASKPASS = ROOT / "automation" / "askpass.sh"
REPOS = {
    "ios": (IOS, "DarulIrfanApp/Resources/SeedData"),
    "android": (ROOT / "DarulIrfanAndroid", "app/src/main/assets/seed"),
    "harmony": (ROOT / "DarulIrfanHarmony", "entry/src/main/resources/rawfile/seed"),
    "web": (ROOT / "DarulIrfanWeb", "content"),
}
SYNCED = ["book_pages.json", "book_pages_index.json", "quran_tafsir.json", "tafsir_volumes.json", "manifest.json"]
WEB_URL = "https://darul-irfan-app.wajidmahmoodali1984-e23.workers.dev"
# The Workers/D1 deploy token is the 8th long value in the repository's own
# cloudflare.md (git-ignored), as Tools' cf.sh reads it; the parent folder's
# cloudflare.md holds other keys (R2, RealtimeKit).
CLOUDFLARE = IOS / "cloudflare.md"
CLOUDFLARE_TOKEN_INDEX = 8
WHAT_TO_TEST = ("Akram-ut-Tafaseer, read again from all 31 printed parts and laid out as printed, "
                "including Parah 30 part 2 (Surah Al-Layl to An-Nas), which is new in the app. "
                "Open any ayah's tafsir, or the Library, to read it.")
ATTRIBUTION = "\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"


class Stop(Exception):
    """A step failed; the message says why."""


def log(message: str) -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    line = f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}"
    print(line, flush=True)
    with LOG.open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def load_state() -> dict:
    return json.loads(STATE.read_text(encoding="utf-8")) if STATE.exists() else {"done": []}


def save_state(state: dict) -> None:
    STATE.write_text(json.dumps(state, indent=1), encoding="utf-8")


def sh(args: list, cwd: Path = IOS, env: dict | None = None, timeout: int = 3600, quiet: bool = False) -> str:
    """Run a command; its output tail goes to the log when it fails."""
    shown = " ".join(str(a) for a in args)
    if not quiet:
        log(f"$ {shown}  (in {cwd.name})")
    result = subprocess.run([str(a) for a in args], cwd=cwd, env=env, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=timeout, shell=False)
    if result.returncode != 0:
        tail = "\n".join((result.stdout + "\n" + result.stderr).strip().splitlines()[-25:])
        raise Stop(f"{shown} failed (exit {result.returncode}):\n{tail}")
    return result.stdout


def python(*args: str, cwd: Path = IOS, timeout: int = 7200) -> str:
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    return sh([sys.executable, *args], cwd=cwd, env=env, timeout=timeout)


def npm(*args: str, cwd: Path, env: dict | None = None, timeout: int = 3600) -> str:
    # npm and npx are .cmd files on Windows: run them through cmd.
    return sh(["cmd", "/c", *args], cwd=cwd, env=env, timeout=timeout)


def ssh_env() -> dict:
    # Task Scheduler starts without Git's tools on PATH, and the askpass script
    # needs them (cat, dirname).
    path = str(SSH.parent) + os.pathsep + os.environ.get("PATH", "")
    return dict(os.environ, PATH=path, SSH_ASKPASS=str(ASKPASS), SSH_ASKPASS_REQUIRE="force", DISPLAY=":0")


def amd(command: str, timeout: int = 120) -> str:
    return sh([SSH, "-o", "ConnectTimeout=20", AMD, command], env=ssh_env(), timeout=timeout, quiet=True)


# -- the steps -----------------------------------------------------------------

def amd_status() -> dict | None:
    raw = amd(f"cat {AMD_RUN}/status.json 2>/dev/null || true").strip()
    return json.loads(raw) if raw else None


def preflight() -> None:
    for name, (repo, _) in REPOS.items():
        branch = sh(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=repo, quiet=True).strip()
        if branch != "main":
            raise Stop(f"{name} is on {branch}, not main")
        if sh(["git", "status", "--porcelain"], cwd=repo, quiet=True).strip():
            raise Stop(f"{name} has uncommitted changes; waiting for a person to finish")
        sh(["git", "fetch", "--quiet", "origin"], cwd=repo, quiet=True, timeout=300)
        behind, ahead = sh(["git", "rev-list", "--left-right", "--count", "origin/main...HEAD"], cwd=repo,
                           quiet=True).split()
        if behind != "0" or ahead != "0":
            raise Stop(f"{name} is {ahead} ahead / {behind} behind GitHub; waiting for a person")
    log("repositories: on main, clean, level with GitHub")


def fetch_pages(target: Path) -> int:
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)
    env = ssh_env()
    archive = target.parent / "pages.tar"
    with archive.open("wb") as handle:
        result = subprocess.run([str(SSH), "-o", "ConnectTimeout=20", AMD, f"tar -C {AMD_RUN} -cf - pages"],
                                stdout=handle, stderr=subprocess.PIPE, env=env, timeout=3600)
    if result.returncode != 0:
        raise Stop(f"copying the pages from amd failed: {result.stderr.decode(errors='replace')[-400:]}")
    sh(["tar", "-xf", archive.name], cwd=target.parent, quiet=True)
    archive.unlink()
    pages = target.parent / "pages"
    if pages != target:
        shutil.rmtree(target); pages.rename(target)
    count = len(list(target.glob("*.json")))
    log(f"copied {count:,} page readings from amd")
    if not count:
        raise Stop("amd's run folder has no pages")
    return count


def bump_manifests() -> int:
    versions = set()
    for name, (repo, seed) in REPOS.items():
        path = repo / seed / "manifest.json"
        versions.add(json.loads(path.read_text(encoding="utf-8"))["version"])
    if len(versions) != 1:
        raise Stop(f"the four manifests disagree before the bump: {sorted(versions)}")
    version = versions.pop() + 1
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for name, (repo, seed) in REPOS.items():
        path = repo / seed / "manifest.json"
        raw = path.read_text(encoding="utf-8")
        raw = re.sub(r'"version":\s*\d+', f'"version": {version}', raw, count=1)
        raw = re.sub(r'"generatedAt":\s*"[^"]*"', f'"generatedAt": "{stamp}"', raw, count=1)
        path.write_text(raw, encoding="utf-8", newline="")
    log(f"manifest {version} on all four platforms")
    return version


def same_on_all_platforms() -> None:
    import hashlib
    for file in SYNCED:
        digests = {name: hashlib.sha256((repo / seed / file).read_bytes()).hexdigest()
                   for name, (repo, seed) in REPOS.items()}
        if len(set(digests.values())) != 1:
            raise Stop(f"{file} differs between platforms: {digests}")
    log("the changed seed files are byte-identical on all four platforms")


def checks() -> None:
    python("Tools/ContentIntegrity/check_content.py")
    python("Tools/Hadith/hadith_gate.py")
    web = REPOS["web"][0]
    npm("npm", "test", cwd=web)
    npm("npm", "run", "build", cwd=web)
    npm("node", "scripts/verify-distribution.mjs", cwd=web)
    log("content checks, web tests and web build pass")


def next_tag() -> str:
    tags = sh(["git", "tag", "--list", "v*"], quiet=True).split()
    versions = sorted(tuple(int(x) for x in m.groups()) for t in tags if (m := re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", t)))
    major, minor, patch = versions[-1] if versions else (1, 0, 0)
    return f"v{major}.{minor}.{patch + 1}"


def commit_push_tag(state: dict, version: int, report: dict) -> None:
    parts = report.get("parts") or "all printed parts"
    for name, (repo, seed) in REPOS.items():
        sh(["git", "add", "--", seed], cwd=repo, quiet=True)
        if name == "ios":
            sh(["git", "add", "--", "Tools/Library", "Tools/Release"], cwd=repo, quiet=True)
            title = "Akram-ut-Tafaseer read again from the printed volumes; Parah 30 part 2 added"
        else:
            title = f"Seeds: Akram-ut-Tafaseer read again from the printed volumes (manifest {version})"
        body = (f"Claude's reading of {parts} of Akram-ut-Tafaseer replaces the earlier OCR text, laid out "
                "as printed. The per-ayah rows and the volume links are re-keyed from it "
                f"(Tools/Library/segment_akram_tafaseer.py). Manifest {version}.")
        if not sh(["git", "diff", "--cached", "--name-only"], cwd=repo, quiet=True).strip():
            log(f"{name}: nothing to commit"); continue
        sh(["git", "commit", "-q", "-m", title + "\n\n" + body + ATTRIBUTION], cwd=repo)
    for name, (repo, _) in REPOS.items():
        sh(["git", "push", "-q", "origin", "main"], cwd=repo, timeout=900)
    tag = next_tag()
    sh(["git", "tag", "-a", tag, "-m", f"{tag}: Akram-ut-Tafaseer from the printed volumes"])
    sh(["git", "push", "-q", "origin", tag], timeout=300)
    state["tag"] = tag
    log(f"committed and pushed the four repositories; tagged {tag}")


class Waiting(Exception):
    """Not a failure: an outside condition to wait for (logged once, retried next run)."""


def tag_build(tag: str) -> str | None:
    """A TestFlight build Codemagic already started for this tag (codemagic.yaml
    triggers ios-testflight on v* tags when its webhook is connected)."""
    for build in codemagic.call("GET", f"/builds?appId={codemagic.APP_ID}").get("builds", [])[:10]:
        if build.get("fileWorkflowId") == "ios-testflight" and build.get("tag") == tag:
            return build.get("_id")
    return None


def testflight_release(state: dict) -> None:
    if not state.get("codemagic_build"):
        started = datetime.now(timezone.utc)
        existing = tag_build(state["tag"])
        if existing:
            state["codemagic_build"] = existing
        else:
            request = urllib.request.Request(
                codemagic.API + "/builds", method="POST",
                data=json.dumps({"appId": codemagic.APP_ID, "workflowId": "ios-testflight", "branch": "main"}).encode(),
                headers={"x-auth-token": codemagic.token(), "Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    state["codemagic_build"] = json.loads(response.read() or b"{}").get("buildId")
            except urllib.error.HTTPError as error:
                body = error.read()[:300].decode(errors="replace")
                if error.code == 402:
                    # Codemagic's free minutes are used up or billing is off: the owner's
                    # call. Retried every run until builds are accepted again.
                    raise Waiting(f"Codemagic will not build (HTTP 402, billing): {body}")
                raise Stop(f"Codemagic refused the build: HTTP {error.code} {body}")
        state["codemagic_started"] = started.isoformat()
        save_state(state)
        log(f"Codemagic ios-testflight: {state['codemagic_build']}")
    while True:
        build = codemagic.build(state["codemagic_build"])
        if build.get("status") in codemagic.FINAL:
            break
        time.sleep(60)
    if build.get("status") != "finished":
        failed = state.pop("codemagic_build"); save_state(state)
        raise Stop(f"Codemagic build {failed} ended {build.get('status')}; see `codemagic.py log {failed}`")
    log("Codemagic build finished and uploaded")
    started = datetime.fromisoformat(state["codemagic_started"])
    number = None
    for _ in range(90):
        for candidate in testflight.newest(5):
            if datetime.fromisoformat(candidate["uploaded"]) > started:
                number = candidate["number"]; break
        if number:
            break
        time.sleep(60)
    if not number:
        raise Stop("the new build did not appear in App Store Connect within 90 minutes")
    state["build_number"] = number; save_state(state)
    if testflight.release(number, WHAT_TO_TEST) != 0:
        raise Stop(f"TestFlight release of build {number} did not complete")
    log(f"build {number} is with the testers (external review submitted)")


def cloudflare_env() -> dict:
    text = CLOUDFLARE.read_text(encoding="utf-8")
    values = re.findall(r"[A-Za-z0-9_-]{30,}", text)
    return dict(os.environ, CLOUDFLARE_ACCOUNT_ID=values[0], CLOUDFLARE_API_TOKEN=values[CLOUDFLARE_TOKEN_INDEX])


def web_deploy() -> None:
    web = REPOS["web"][0]
    npm("npx", "wrangler", "deploy", cwd=web, env=cloudflare_env(), timeout=1800)
    npm("node", "scripts/check-deployed.mjs", WEB_URL, cwd=web)
    log("web app deployed and serving the new content")


# -- runs ---------------------------------------------------------------------

def run() -> int:
    state = load_state()
    if state.get("released"):
        print(f"released {state.get('tag')} (build {state.get('build_number')}); nothing to do")
        return 0
    status = amd_status()
    if not status or not status.get("finished"):
        note = "not started" if not status else (f"{status['done_pages']:,}/{status['total_pages']:,} pages, "
                                                  f"${status['spent_usd']}")
        if state.get("last_wait") != note:
            log(f"waiting for amd's re-read: {note}")
            state["last_wait"] = note; save_state(state)
        return 0
    done = state["done"]
    if "committed" not in done:
        preflight()
        log(f"amd's re-read is finished: {status['done_pages']:,} pages, ${status['spent_usd']}, "
            f"{status['queued_pages']:,} left for later, {status['failed_pages']} failed")
        pages = WORK / "pages"
        fetch_pages(pages)
        python("Tools/Library/ingest_claude_pages.py", "--pages", str(pages), "--add-pages", "--write")
        python("Tools/Library/segment_akram_tafaseer.py", "--write", "--report", str(WORK / "segment_report.json"))
        version = bump_manifests()
        same_on_all_platforms()
        checks()
        left = status["queued_pages"]
        report = {"parts": "all 31 printed parts" if not left else f"most of the 31 printed parts ({left:,} pages wait for the next re-read)"}
        commit_push_tag(state, version, report)
        done.append("committed"); save_state(state)
    # The web app does not depend on the iOS build: deploy it first.
    if "web" not in done:
        web_deploy()
        done.append("web"); save_state(state)
    if "testflight" not in done:
        try:
            testflight_release(state)
        except Waiting as reason:
            if state.get("last_wait") != str(reason):
                log(f"waiting: {reason}")
                state["last_wait"] = str(reason); save_state(state)
            return 0
        done.append("testflight"); save_state(state)
    state["released"] = True; save_state(state)
    log(f"RELEASED {state.get('tag')}: TestFlight build {state.get('build_number')}, web app deployed")
    return 0


def dry_run(pages_dir: Path | None) -> int:
    """Every check the run makes, changing nothing: amd, the repositories, the
    tools in report mode on the readings (or a sample folder), and the three
    services' credentials."""
    problems = []
    def attempt(label, action):
        try:
            result = action()
            log(f"dry-run ok: {label}" + (f" -> {result}" if result not in (None, "") else ""))
        except Exception as error:  # noqa: BLE001 - a dry run reports everything
            problems.append(label); log(f"dry-run PROBLEM: {label}: {error}")
    attempt("amd status", lambda: amd_status() or "not started yet")
    attempt("repositories clean and level", preflight)
    sample = pages_dir
    if sample is None:
        sample = Path(tempfile.mkdtemp(prefix="akram-dry-")) / "pages"
        attempt("copy pages from amd", lambda: fetch_pages(sample))
    attempt("ingest (report only)", lambda: python("Tools/Library/ingest_claude_pages.py", "--pages", str(sample),
                                                    "--add-pages").strip().splitlines()[-1])
    attempt("segment (report only)", lambda: python("Tools/Library/segment_akram_tafaseer.py") and "built")
    attempt("content checks", lambda: python("Tools/ContentIntegrity/check_content.py").strip().splitlines()[-1])
    attempt("next tag", next_tag)
    attempt("Codemagic API", lambda: len(codemagic.call("GET", f"/builds?appId={codemagic.APP_ID}").get("builds", [])))
    attempt("App Store Connect API", lambda: testflight.newest(1))
    attempt("Cloudflare deploy token", lambda: "logged in" in npm("npx", "wrangler", "whoami", cwd=REPOS["web"][0],
                                                                  env=cloudflare_env(), timeout=300) and "accepted")
    log(f"dry-run finished: {len(problems)} problem(s) {problems}")
    return 1 if problems else 0


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    args = sys.argv[1:]
    WORK.mkdir(parents=True, exist_ok=True)
    if not args or args[0] == "status":
        print(json.dumps({"state": load_state(), "amd": amd_status()}, indent=1))
        return 0
    if LOCK.exists() and time.time() - LOCK.stat().st_mtime < 6 * 3600:
        print("another run is in progress"); return 0
    LOCK.write_text(str(os.getpid()), encoding="utf-8")
    try:
        if args[0] == "run":
            return run()
        if args[0] == "dry-run":
            pages = Path(args[args.index("--pages") + 1]) if "--pages" in args else None
            return dry_run(pages)
        sys.exit(__doc__)
    except Stop as stop:
        log(f"STOPPED: {stop}")
        return 1
    except SystemExit as stop:      # codemagic.py exits on an HTTP error
        if stop.code in (0, None):
            raise
        log(f"STOPPED: {stop.code}")
        return 1
    finally:
        LOCK.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
