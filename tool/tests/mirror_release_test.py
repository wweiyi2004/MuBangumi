"""Publication behavior tests using fake HTTP responses; never writes remotely."""
import hashlib
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mirror_release as mirror

DATA = b"verified installation package"
NAME = "MuBangumi-2.3.1-build4029-windows-x64.zip"
TAG = "v2.3.1+4029"
ASSET = {"name": NAME, "size": len(DATA),
         "digest": f"sha256:{hashlib.sha256(DATA).hexdigest()}",
         "browser_download_url": f"https://github.com/wweiyi2004/MuBangumi/releases/download/{TAG}/{NAME}"}
RELEASE = {"tag_name": TAG, "name": TAG, "body": "- Changes", "assets": [ASSET]}


class Response:
    def __init__(self, status=200, data=None, content=DATA, headers=None):
        self.status_code = status
        self.data = data
        self.content = content
        self.headers = headers or {}

    def json(self):
        return self.data

    def iter_content(self, _):
        yield self.content

    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass


class MirrorTests(unittest.TestCase):
    def test_api_errors_explain_missing_permissions_without_leaking_token(self):
        error = mirror.gitee_failure(Response(status=403, data={
            "message": "Missing projects scope for token sensitive-token"}),
            "GET", "sensitive-token")
        self.assertIn("projects", str(error))
        self.assertNotIn("sensitive-token", str(error))

    def test_rejects_untrusted_assets_and_missing_hash(self):
        self.assertEqual(mirror.select_assets(RELEASE), [ASSET])
        for changes in ({"digest": None}, {"size": 0},
                        {"browser_download_url": "https://evil.test/package.zip"}):
            with self.assertRaises(ValueError):
                mirror.select_assets(RELEASE | {"assets": [ASSET | changes]})
        with self.assertRaises(ValueError):
            mirror.select_assets(RELEASE | {"prerelease": True})

    def test_manifest_keeps_original_checksums_and_notes(self):
        assets = [ASSET | {"mirror_url": mirror.public_url("owner/MuBangumi", TAG, NAME)}]
        body = mirror.release_body(RELEASE, "owner/MuBangumi", assets)
        encoded = body.split(mirror.MANIFEST_START)[1].split(mirror.MANIFEST_END)[0]
        data = json.loads(encoded)
        self.assertEqual(data["assets"][0]["digest"], ASSET["digest"])
        self.assertEqual(data["body"], RELEASE["body"])
        self.assertIn("%2B4029", data["assets"][0]["mirror_url"])

    def test_checks_anonymous_download_integrity(self):
        with patch.object(mirror.requests, "get", return_value=Response()) as get:
            mirror.verify_download("https://gitee.com/example", ASSET)
            self.assertNotIn("Authorization", get.call_args.kwargs["headers"])
        with patch.object(mirror.requests, "get", return_value=Response(content=b"bad")):
            with self.assertRaises(ValueError):
                mirror.verify_download("https://gitee.com/example", ASSET)

    def test_range_probe_requires_correct_206(self):
        for status, headers, expected in [
            (206, {"Content-Range": f"bytes 0-0/{len(DATA)}"}, True),
            (200, {}, False), (206, {"Content-Range": "bytes 0-0/999"}, False)
        ]:
            with patch.object(mirror.requests, "get", return_value=Response(status=status, headers=headers)):
                self.assertEqual(mirror.supports_resume("https://gitee.com/example", len(DATA)), expected)

    @patch.dict(mirror.os.environ, {"GITEE_TOKEN": "test-token"})
    def test_failed_public_verification_never_publishes_manifest(self):
        def verify(_url, _asset, destination=None):
            if destination is not None:
                destination.write_bytes(DATA)
            else:
                raise ValueError("checksum")
        with patch.object(mirror.requests, "get", return_value=Response(data=RELEASE)), \
             patch.object(mirror, "api", side_effect=[None, {"id": 1}, []]) as api, \
             patch.object(mirror.requests, "post", return_value=Response()), \
             patch.object(mirror, "verify_download", side_effect=verify):
            with self.assertRaises(ValueError):
                mirror.mirror("owner/MuBangumi", TAG)
            self.assertFalse(any(call.args[0] == "PATCH" for call in api.call_args_list))

    @patch.dict(mirror.os.environ, {"GITEE_TOKEN": "test-token"})
    def test_existing_attachment_is_verified_and_not_uploaded_again(self):
        expected_assets = [ASSET | {"mirror_url": mirror.public_url("owner/MuBangumi", TAG, NAME)}]
        expected_body = mirror.release_body(RELEASE, "owner/MuBangumi", expected_assets)
        with patch.object(mirror.requests, "get", side_effect=[Response(data=RELEASE), Response(data={"body": expected_body})]), \
             patch.object(mirror, "api", side_effect=[{"id": 1}, [{"name": NAME}], {}]) as api, \
             patch.object(mirror.requests, "post") as upload, \
             patch.object(mirror, "verify_download") as verify, \
             patch.object(mirror, "supports_resume", return_value=True):
            mirror.mirror("owner/MuBangumi", TAG)
            upload.assert_not_called()
            self.assertEqual(verify.call_count, 2)
            self.assertEqual(api.call_args.args[0], "PATCH")
            self.assertFalse(api.call_args.kwargs["json"]["prerelease"])

    def test_dry_run_never_writes_gitee(self):
        with patch.object(mirror.requests, "get", return_value=Response(data=RELEASE)), \
             patch.object(mirror, "api") as api, \
             patch.object(mirror, "verify_download"):
            mirror.mirror("owner/MuBangumi", TAG, dry_run=True)
            api.assert_not_called()


if __name__ == "__main__":
    unittest.main()
