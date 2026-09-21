"""Copy an immutable GitHub release to Gitee and publish verified update metadata.

Tokens are read from GITEE_TOKEN / GH_TOKEN, never from command-line arguments.
The public update manifest is written only after every mirrored file can be
downloaded anonymously and its SHA-256 matches the original release.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import time
from urllib.parse import quote, unquote, urlsplit

import requests
from requests_toolbelt.multipart.encoder import MultipartEncoder, MultipartEncoderMonitor

GITHUB_REPOSITORY = "wweiyi2004/MuBangumi"
MANIFEST_START = "<!-- mubangumi-update-v1\n"
MANIFEST_END = "\n-->"
MAX_BYTES = 512 * 1024 * 1024


def valid_repository(value: str) -> bool:
    return bool(re.fullmatch(r"[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+", value)) and all(
        part not in (".", "..") for part in value.split("/")
    )


def select_assets(release: dict) -> list[dict]:
    tag = release.get("tag_name", "")
    if not re.fullmatch(r"v?\d+(?:\.\d+)*(?:\+\d+)?", tag):
        raise ValueError("Release tag must be a stable application version")
    if release.get("draft") or release.get("prerelease"):
        raise ValueError("Only published stable releases can be mirrored")
    version = tag.removeprefix("v").split("+")[0]
    selected = []
    for asset in release.get("assets", []):
        name = asset.get("name", "")
        if not re.fullmatch(
            rf"MuBangumi-{re.escape(version)}-build\d+-(?:windows-x64\.zip|android(?:-(?:arm64-v8a|armeabi-v7a|x86_64))?\.apk)", name
        ):
            continue
        url = urlsplit(asset.get("browser_download_url", ""))
        expected = f"/{GITHUB_REPOSITORY}/releases/download/{tag}/{name}"
        if (url.scheme != "https" or url.netloc != "github.com" or
                unquote(url.path) != expected or url.query or url.fragment):
            raise ValueError(f"Unexpected original download URL: {name}")
        if not isinstance(asset.get("size"), int) or not 0 < asset["size"] <= MAX_BYTES:
            raise ValueError(f"Invalid artifact size: {name}")
        if not re.fullmatch(r"sha256:[a-fA-F0-9]{64}", asset.get("digest") or ""):
            raise ValueError(f"Missing GitHub SHA-256 digest: {name}")
        selected.append(asset)
    if not selected or len({a["name"] for a in selected}) != len(selected):
        raise ValueError("No uniquely named installable artifacts found")
    return sorted(selected, key=lambda asset: asset['size'])


def public_url(repository: str, tag: str, name: str) -> str:
    return f"https://gitee.com/{repository}/releases/download/{quote(tag, safe='')}/{quote(name, safe='')}"


def gitee_failure(response, operation: str, token: str) -> RuntimeError:
    detail = ""
    try:
        payload = response.json()
        if isinstance(payload, dict):
            detail = "; ".join(str(payload[key]) for key in
                               ("message", "error", "error_description") if payload.get(key))
    except ValueError:
        detail = "non-JSON response"
    if token:
        detail = detail.replace(token, "[redacted]")
    return RuntimeError(f"Gitee {operation} failed (HTTP {response.status_code})" +
                        (f": {detail[:400]}" if detail else ""))


def api(method: str, path: str, token: str, **kwargs):
    # Authentication is only ever sent to the fixed API origin, never attachment
    # CDN redirects. Do not print response bodies or exceptions containing URLs.
    for attempt in range(3):
        response = requests.request(method, f"https://gitee.com/api/v5/{path}",
            headers={"Authorization": f"Bearer {token}", "Accept": "application/json",
                     "User-Agent": "MuBangumi-ReleaseMirror/1.0"},
            timeout=(15, 60), allow_redirects=False, **kwargs)
        transient = response.status_code in (429, 502, 503, 504) or (
            response.status_code == 403 and
            "json" not in response.headers.get("Content-Type", "").lower())
        if method != "GET" or not transient or attempt == 2:
            break
        print(f"Gitee returned HTTP {response.status_code}; retrying metadata request", flush=True)
        time.sleep(2 ** attempt)
    if response.status_code == 404 and method == "GET":
        return None
    if not 200 <= response.status_code < 300:
        raise gitee_failure(response, method, token)
    return response.json() if response.content else None


def verify_download(url: str, asset: dict, destination: Path | None = None) -> None:
    digest = hashlib.sha256()
    count = 0
    with requests.get(url, stream=True, timeout=(15, 60),
                      headers={"Accept-Encoding": "identity"}) as response:
        if response.status_code != 200:
            raise RuntimeError(f"Public artifact download failed (HTTP {response.status_code})")
        output = destination.open("wb") if destination else None
        try:
            for chunk in response.iter_content(1024 * 1024):
                count += len(chunk)
                if count > asset["size"]:
                    raise ValueError("Artifact exceeds declared size")
                digest.update(chunk)
                if output:
                    output.write(chunk)
        finally:
            if output:
                output.close()
    if count != asset["size"] or f"sha256:{digest.hexdigest()}" != asset["digest"].lower():
        raise ValueError(f"Artifact checksum mismatch: {asset['name']}")


def supports_resume(url: str, size: int) -> bool:
    # Probe the public stable URL, including all CDN redirects. Close immediately
    # if the server ignores Range instead of downloading the entire artifact twice.
    with requests.get(url, headers={"Range": "bytes=0-0", "Accept-Encoding": "identity"},
                      stream=True, timeout=(15, 30)) as response:
        return (response.status_code == 206 and
                response.headers.get("Content-Range") == f"bytes 0-0/{size}")


def release_body(original: dict, repository: str, assets: list[dict]) -> str:
    manifest = {"schema": 1, "repository": repository,
        "tag_name": original["tag_name"], "name": original.get("name"),
        "body": original.get("body") or "", "html_url": original.get("html_url"),
        "assets": assets}
    return ((original.get("body") or "") + "\n\n" + MANIFEST_START +
            json.dumps(manifest, ensure_ascii=False, separators=(",", ":")) + MANIFEST_END)


def upload_attachment(base: str, release_id: int, token: str, path: Path) -> None:
    started = time.monotonic()
    last_report = 0

    def progress(monitor):
        nonlocal last_report
        elapsed = time.monotonic() - started
        if elapsed > 180:
            raise RuntimeError(f"Gitee upload exceeded 180 seconds: {path.name}; "
                               f"sent {monitor.bytes_read}/{monitor.len} bytes. "
                               "Retry from a faster network or upload this same file in Gitee's release page.")
        if monitor.bytes_read - last_report >= 5 * 1024 * 1024:
            last_report = monitor.bytes_read
            print(f"Uploading {path.name}: {monitor.bytes_read}/{monitor.len} bytes", flush=True)

    print(f"Uploading attachment: {path.name} ({path.stat().st_size} bytes)", flush=True)
    with path.open("rb") as stream:
        encoder = MultipartEncoder(fields={"file": (path.name, stream, "application/octet-stream")})
        monitor = MultipartEncoderMonitor(encoder, progress)
        response = requests.post(f"https://gitee.com/api/v5/{base}/{release_id}/attach_files",
            headers={"Authorization": f"Bearer {token}", "Content-Type": encoder.content_type},
            data=monitor, timeout=(15, 60), allow_redirects=False)
        if not 200 <= response.status_code < 300:
            raise gitee_failure(response, "attachment upload", token)


def mirror(repository: str, tag: str | None, dry_run: bool = False) -> None:
    if not valid_repository(repository):
        raise ValueError("Repository must be owner/name")
    token = os.environ.get("GITEE_TOKEN", "")
    if not dry_run and not token:
        raise ValueError("Set GITEE_TOKEN in the environment or GitHub Actions Secrets")
    headers = {"Accept": "application/vnd.github+json"}
    if os.environ.get("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {os.environ['GH_TOKEN']}"
    endpoint = f"tags/{quote(tag, safe='')}" if tag else "latest"
    response = requests.get(f"https://api.github.com/repos/{GITHUB_REPOSITORY}/releases/{endpoint}",
                            headers=headers, timeout=(15, 60))
    if response.status_code != 200:
        raise RuntimeError(f"GitHub release lookup failed (HTTP {response.status_code})")
    original = response.json()
    selected = select_assets(original)
    tag = original["tag_name"]
    base = f"repos/{repository}/releases"
    with tempfile.TemporaryDirectory(prefix="mubangumi-mirror-") as temporary:
        directory = Path(temporary)
        for asset in selected:
            verify_download(asset["browser_download_url"], asset, directory / asset["name"])
            print(f"Verified original: {asset['name']} ({asset['size']} bytes)", flush=True)
        if dry_run:
            print(f"Dry run complete: {len(selected)} verified artifacts; no remote changes.")
            return
        existing = api("GET", f"{base}/tags/{quote(tag, safe='')}", token)
        if existing is None:
            existing = api("POST", base, token, json={"tag_name": tag,
                "target_commitish": "main", "name": original.get("name") or tag,
                "body": "安装包同步中，请暂时使用 GitHub 发布页。", "prerelease": True})
        release_id = int(existing["id"])
        print(f"Preparing Gitee release {release_id}", flush=True)
        attachments = api("GET", f"{base}/{release_id}/attach_files", token) or []
        if not isinstance(attachments, list):
            raise ValueError("Unexpected Gitee attachment list")
        names = {a["name"] for a in attachments}
        mirrored = []
        for asset in selected:
            name = asset["name"]
            if name not in names:
                upload_attachment(base, release_id, token, directory / name)
            # Existing files are verified too; never overwrite a conflicting file.
            url = public_url(repository, tag, name)
            verify_download(url, asset)
            resumable = supports_resume(url, asset["size"])
            print(f"Verified public mirror: {name}; Range supported: {resumable}", flush=True)
            mirrored.append({key: asset[key] for key in ("name", "size", "digest", "browser_download_url")} |
                            {"mirror_url": url})
        body = release_body(original, repository, mirrored)
        api("PATCH", f"{base}/{release_id}", token, json={"tag_name": tag,
            "name": original.get("name") or tag, "body": body, "prerelease": False})
        # Do not announce success until clients can read the manifest anonymously.
        check = requests.get(f"https://gitee.com/api/v5/{base}/tags/{quote(tag, safe='')}", timeout=(15, 30))
        if check.status_code != 200 or check.json().get("body") != body:
            raise RuntimeError("Published metadata could not be verified anonymously")
        print(f"Published verified mirror: https://gitee.com/{repository}/releases/tag/{quote(tag, safe='')}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True, help="Gitee owner/repository")
    parser.add_argument("--tag", help="GitHub release tag (default: latest stable)")
    parser.add_argument("--dry-run", action="store_true", help="Download and verify originals without publishing")
    args = parser.parse_args()
    try:
        mirror(args.repository, args.tag, args.dry_run)
    except (ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    except requests.RequestException:
        # Request exceptions may contain signed CDN URLs; avoid logging them.
        print("Network request failed; verify connectivity and rerun to resume publication.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
