"""HTTP client: 429/5xx retries, Retry-After, backoff, failure accounting.

Runs against a localhost mock server (127.0.0.1 only) - no external network.
"""
from __future__ import annotations

import json
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

from src.config import ApiConfig
from src.http_client import BangumiHttpClient, HttpError, RateLimiter, parse_retry_after


class _Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        status, headers, body = (
            self.server.scenario.pop(0) if self.server.scenario else (500, {}, b"")
        )
        self.send_response(status)
        for key, value in headers.items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # silence request logs
        pass


@pytest.fixture
def mock_server():
    server = HTTPServer(("127.0.0.1", 0), _Handler)
    server.scenario = []
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield server
    server.shutdown()


def _client(server, **api_overrides):
    api = ApiConfig(
        base_url=f"http://127.0.0.1:{server.server_port}",
        qps=10000,  # disable the QPS gate for retry tests
        retry_base_seconds=0.01,
        retry_jitter_seconds=0.0,
        max_retries=3,
        **api_overrides,
    )
    return BangumiHttpClient(api, stage="test")


def test_retry_429_respects_retry_after(mock_server):
    mock_server.scenario = [
        (429, {"Retry-After": "1"}, b""),
        (200, {}, b'{"ok": true}'),
    ]
    client = _client(mock_server)
    started = time.monotonic()
    result = client.get_json("/x")
    elapsed = time.monotonic() - started
    assert result == {"ok": True}
    assert elapsed >= 0.9  # waited for Retry-After
    assert client.stats.snapshot() == {"success": 1, "failed": 0, "retries": 1, "skipped": 0}


def test_retry_500_then_success(mock_server):
    mock_server.scenario = [(500, {}, b""), (200, {}, b'{"ok": 1}')]
    client = _client(mock_server)
    assert client.get_json("/x") == {"ok": 1}
    assert client.stats.retries == 1


def test_retry_exhaustion_raises(mock_server):
    mock_server.scenario = [(429, {"Retry-After": "0.01"}, b"")] * 5
    client = _client(mock_server)
    with pytest.raises(HttpError) as exc_info:
        client.get_json("/x")
    assert exc_info.value.status == 429
    assert exc_info.value.retries == 3  # max_retries = 3
    assert client.stats.failed == 1
    assert client.stats.retries == 3


def test_404_no_retry_permanent(mock_server):
    mock_server.scenario = [(404, {}, b"not found")]
    client = _client(mock_server)
    with pytest.raises(HttpError) as exc_info:
        client.get_json("/x")
    assert exc_info.value.status == 404
    assert exc_info.value.retries == 0
    assert exc_info.value.is_permanent()
    assert client.stats.retries == 0


def test_invalid_json_raises(mock_server):
    mock_server.scenario = [(200, {}, b"<html>not json</html>")]
    client = _client(mock_server)
    with pytest.raises(HttpError):
        client.get_json("/x")
    assert client.stats.retries == 0
    assert client.stats.failed == 1


def test_failure_callback_records(mock_server):
    records = []
    api = ApiConfig(
        base_url=f"http://127.0.0.1:{mock_server.server_port}",
        qps=10000, max_retries=1, retry_base_seconds=0.01, retry_jitter_seconds=0.0,
    )
    client = BangumiHttpClient(api, stage="test", on_failure=records.append)
    mock_server.scenario = [(404, {}, b"gone")]
    with pytest.raises(HttpError):
        client.get_json("/y")
    assert len(records) == 1
    record = records[0]
    assert record["stage"] == "test"
    assert record["status"] == 404
    assert record["url"].endswith("/y")
    assert record["retries"] == 0


def test_failure_log_masks_username_in_collection_url(mock_server):
    """A failure on /v0/users/{username}/collections must never write the
    username into the failure record (URL or message)."""
    records = []
    api = ApiConfig(
        base_url=f"http://127.0.0.1:{mock_server.server_port}",
        qps=10000, max_retries=0, retry_base_seconds=0.01, retry_jitter_seconds=0.0,
    )
    client = BangumiHttpClient(api, stage="test", on_failure=records.append)
    mock_server.scenario = [(404, {}, b"gone")]
    with pytest.raises(HttpError):
        client.get_json("/v0/users/some_secret_username/collections")
    assert len(records) == 1
    serialized = json.dumps(records, ensure_ascii=False)
    assert "some_secret_username" not in serialized
    assert records[0]["url"].endswith("/v0/users/***/collections")
    assert "/v0/users/***/collections" in records[0]["message"]


def test_parse_retry_after_seconds():
    assert parse_retry_after("2") == 2.0
    assert parse_retry_after("0") == 0.0
    assert parse_retry_after(" 1.5 ") == 1.5


def test_parse_retry_after_date():
    assert parse_retry_after("Thu, 01 Jan 2030 00:00:00 GMT") > 0
    assert parse_retry_after("Mon, 01 Jan 2020 00:00:00 GMT") == 0.0  # already past


def test_parse_retry_after_garbage():
    assert parse_retry_after(None) is None
    assert parse_retry_after("") is None
    assert parse_retry_after("not-a-date") is None


def test_rate_limiter_enforces_interval():
    limiter = RateLimiter(4.0)  # 0.25 s between requests
    started = time.monotonic()
    limiter.acquire()
    limiter.acquire()
    elapsed = time.monotonic() - started
    assert elapsed >= 0.2


def test_post_json_sends_body(mock_server):
    seen = {}

    class PostHandler(_Handler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            seen["body"] = self.rfile.read(length).decode()
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"{}")

    server = HTTPServer(("127.0.0.1", 0), PostHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        client = _client(server)
        assert client.post_json("/v0/search/subjects", {"keyword": ""}) == {}
        assert '"keyword"' in seen["body"]
    finally:
        server.shutdown()
