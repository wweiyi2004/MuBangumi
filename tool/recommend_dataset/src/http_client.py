"""Rate-limited HTTP client with exponential backoff and Retry-After support.

Design constraints (see tool/recommend_dataset/README.md):
- global QPS gate shared across threads (default 1.0 req/s)
- retry on 429/5xx with exponential backoff + random jitter
- respect the Retry-After header (seconds or HTTP-date)
- non-retryable statuses (4xx) fail fast and are counted, not retried
- every terminal failure is reported to an on_failure callback so the CLI can
  append to failed_requests.jsonl (never contain usernames or tokens there)
"""
from __future__ import annotations

import random
import re
import threading
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any, Callable, Optional

import requests

RETRYABLE_STATUS = {429, 500, 502, 503, 504}
MAX_RETRY_AFTER_SECONDS = 600.0


def _redact_user_segment(text: str) -> str:
    """Replace username segments in /v0/users/... paths with '***'.

    The failure log must never contain usernames; among the endpoints used
    here only the user-collection endpoint embeds one in its path.
    """
    return re.sub(r"/v0/users/[^/]+", "/v0/users/***", text)


class HttpError(Exception):
    """Final HTTP failure (non-retryable status, exhaustion, or bad response)."""

    def __init__(
        self,
        status: Optional[int],
        message: str,
        retries: int = 0,
        url: str = "",
        response_head: str = "",
    ):
        super().__init__(message)
        self.status = status
        self.retries = retries
        self.url = url
        self.response_head = response_head

    def is_permanent(self) -> bool:
        """4xx (client errors) will never succeed on retry -> permanent."""
        return self.status is not None and 400 <= self.status < 500


class RateLimiter:
    """Min-interval gate shared across threads; enforces the global QPS."""

    def __init__(self, qps: float):
        self._interval = 1.0 / max(qps, 1e-9)
        self._lock = threading.Lock()
        self._next = 0.0

    def acquire(self) -> None:
        with self._lock:
            now = time.monotonic()
            wait = self._next - now
            self._next = max(now, self._next) + self._interval
        if wait > 0:
            time.sleep(wait)


def parse_retry_after(value: Optional[str]) -> Optional[float]:
    """Seconds to wait, from a Retry-After header (plain seconds or HTTP-date)."""
    if not value:
        return None
    text = value.strip()
    try:
        return max(0.0, float(text))
    except ValueError:
        pass
    try:
        parsed = parsedate_to_datetime(text)
        if parsed is None:
            return None
        now = datetime.now(timezone.utc)
        delta = parsed.astimezone(timezone.utc) - now
        return max(0.0, delta.total_seconds())
    except Exception:
        return None


class HttpStats:
    """Thread-safe counters reported at the end of each run."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.success = 0
        self.failed = 0
        self.retries = 0
        self.skipped = 0

    def snapshot(self) -> dict[str, int]:
        with self._lock:
            return {
                "success": self.success,
                "failed": self.failed,
                "retries": self.retries,
                "skipped": self.skipped,
            }


class BangumiHttpClient:
    def __init__(
        self,
        api: "ApiConfig",  # noqa: F821 - TYPE_CHECKING import below
        stage: str,
        on_failure: Optional[Callable[[dict[str, Any]], None]] = None,
    ) -> None:
        from src.config import ApiConfig  # avoid import cycle at module load

        self._api = api
        self._base_url = api.base_url.rstrip("/")
        self._timeout = api.timeout_seconds
        self._max_retries = api.max_retries
        self._retry_base = api.retry_base_seconds
        self._retry_max = api.retry_max_seconds
        self._jitter = api.retry_jitter_seconds
        self._limiter = RateLimiter(api.qps)
        self.stage = stage
        self.stats = HttpStats()
        self._on_failure = on_failure
        self._session = requests.Session()
        self._session.headers.update(
            {
                "User-Agent": api.user_agent,
                "Accept": "application/json",
            }
        )

    def get_json(self, path: str, params: Optional[dict[str, Any]] = None) -> Any:
        return self._request("GET", path, params=params)

    def post_json(self, path: str, body: dict[str, Any]) -> Any:
        return self._request("POST", path, body=body)

    def _request(
        self,
        method: str,
        path: str,
        params: Optional[dict[str, Any]] = None,
        body: Optional[dict[str, Any]] = None,
    ) -> Any:
        url = self._base_url + path
        retries = 0
        while True:
            self._limiter.acquire()
            try:
                resp = self._session.request(
                    method, url, params=params, json=body, timeout=self._timeout
                )
            except (requests.exceptions.Timeout, requests.exceptions.ConnectionError) as exc:
                if retries >= self._max_retries:
                    self._mark_failure(url, params, None, f"network error: {exc}", retries)
                    raise HttpError(None, f"network error after {retries} retries: {exc}",
                                    retries=retries, url=url)
                retries += 1
                self.stats.retries += 1
                time.sleep(self._backoff(retries))
                continue

            if 200 <= resp.status_code < 300:
                self.stats.success += 1
                try:
                    return resp.json()
                except ValueError:
                    head = resp.text[:200]
                    self._mark_failure(url, params, resp.status_code,
                                       "response is not valid JSON", retries, head)
                    raise HttpError(resp.status_code, f"invalid JSON response for {path}",
                                    retries=retries, url=url, response_head=head)

            if resp.status_code in RETRYABLE_STATUS:
                if retries >= self._max_retries:
                    head = resp.text[:200]
                    self._mark_failure(url, params, resp.status_code,
                                       f"HTTP {resp.status_code} after {retries} retries",
                                       retries, head)
                    raise HttpError(resp.status_code,
                                    f"HTTP {resp.status_code} for {path} after {retries} retries",
                                    retries=retries, url=url, response_head=head)
                retries += 1
                self.stats.retries += 1
                delay = parse_retry_after(resp.headers.get("Retry-After"))
                if delay is None:
                    delay = self._backoff(retries)
                delay = min(delay, MAX_RETRY_AFTER_SECONDS)
                time.sleep(delay)
                continue

            # Non-retryable failure (e.g. 403/404/400).
            head = resp.text[:200]
            self._mark_failure(url, params, resp.status_code,
                               f"HTTP {resp.status_code} for {path}", retries, head)
            raise HttpError(resp.status_code, f"HTTP {resp.status_code} for {path}",
                            retries=retries, url=url, response_head=head)

    def _backoff(self, attempt: int) -> float:
        exp = min(self._retry_max, self._retry_base * (2 ** (attempt - 1)))
        return exp + random.uniform(0.0, self._jitter)

    def _mark_failure(
        self,
        url: str,
        params: Optional[dict[str, Any]],
        status: Optional[int],
        message: str,
        retries: int,
        response_head: str = "",
    ) -> None:
        self.stats.failed += 1
        if self._on_failure is None:
            return
        self._on_failure(
            {
                "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "stage": self.stage,
                "url": _redact_user_segment(url),
                "params": params,
                "status": status,
                "message": _redact_user_segment(message),
                "retries": retries,
                "response_head": _redact_user_segment(response_head),
            }
        )
