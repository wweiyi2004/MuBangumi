#!/usr/bin/env python3
"""Phase 1b: collect public user-anime interactions via seed users.

Data source: GET /v0/users/{username}/collections (subject_type=2) - the
official public API, no authentication required for public collections, no
HTML scraping. Users must be provided in seed_users.txt (one per line, '#'
comments allowed). Bangumi OpenAPI does not enumerate users; for personal
research, collect_user_seeds.py can build a local seed list from authors who
appear in the publicly accessible community-topic JSON feed. The resulting
dataset remains a biased sample of community-active users.

Privacy: usernames are immediately replaced by a pseudonymous anonymous_user_id
(SHA-256(salt + username)). The salt lives only in the local data directory.
User comments/tags/private flags in the API response are dropped at the model
layer and never persisted. The seed_users table in the checkpoint database
keeps username bookkeeping locally for resume, but nothing user-identifying is
ever exported.

Resume: pagination offset per (user, collection type) is checkpointed; a
crash mid-run continues from the stored offsets, and re-running after
completion only picks up nothing new unless --refetch is given.

Usage:
  python tool/recommend_dataset/collect_interactions.py --config dataset_config.json
  python tool/recommend_dataset/collect_interactions.py --config dataset_config.json --users seed_users.txt
"""
from __future__ import annotations

import argparse
import json
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from src import anon_id, bangumi, db, http_client, weights
from src.config import load_config


class FailLog:
    """Append-only failure log, one JSON object per line (thread-safe)."""

    def __init__(self, path: Path) -> None:
        self._path = path
        self._lock = threading.Lock()
        path.parent.mkdir(parents=True, exist_ok=True)

    def append(self, record: dict) -> None:
        with self._lock:
            with self._path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(record, ensure_ascii=False) + "\n")


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds")


def read_seed_users(path: Path) -> list[str]:
    if not path.exists():
        raise SystemExit(f"seed users file not found: {path}")
    users: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        name = line.strip()
        if not name or name.startswith("#"):
            continue
        if name not in users:
            users.append(name)
    return users


def prioritize_seed_users(
    store,
    salt: str,
    users: list[str],
    *,
    new_users_first: bool = False,
) -> list[str]:
    """Put budget-efficient resumable users first without exposing names.

    Once an API total is known, users closest to completion are preferred.
    This maximizes the number of scientifically usable complete profiles per
    request instead of spending the whole budget on a few extreme outliers.
    Legacy rows with no known total retain the old largest-offset-first order.
    """
    ranked: list[tuple[tuple[int, int, int, int, int, str], str]] = []
    for username in users:
        anonymous_id = anon_id.anonymous_user_id(username, salt)
        record = store.seed_user_record(username)
        checkpoint = store.get_checkpoint(f"collections:{anonymous_id}:all")
        try:
            saved_offset = int(checkpoint or 0)
        except (TypeError, ValueError):
            saved_offset = 0
        if record is None:
            group = 0 if new_users_first else 1
            items = 0
            total_reported = None
        elif record["is_complete"] or record["status"] == "unavailable":
            group = 2
            items = int(record["items_fetched"] or 0)
            total_reported = record.get("total_reported")
        else:
            group = 1 if new_users_first else 0
            items = int(record["items_fetched"] or 0)
            total_reported = record.get("total_reported")
        known_total = total_reported is not None
        remaining = (
            max(0, int(total_reported) - saved_offset)
            if known_total
            else 0
        )
        ranked.append((
            (
                group,
                0 if known_total else 1,
                remaining,
                -saved_offset,
                -items,
                anonymous_id,
            ),
            username,
        ))
    return [username for _, username in sorted(ranked, key=lambda row: row[0])]


def work_user(cfg, store, client, fail_log, salt, username: str, refetch: bool) -> tuple[str, str, str | None]:
    """Fetch one resumable batch; never confuse a run budget with completion."""
    anon = anon_id.anonymous_user_id(username, salt)

    previous = store.seed_user_record(username)
    if (
        previous is not None
        and (previous["is_complete"] or previous["status"] == "unavailable")
        and not refetch
    ):
        return username, "skipped", None
    if refetch:
        store.clear_checkpoints(f"collections:{anon}:")
        previous = None
        store.set_seed_user(
            username,
            anon,
            "pending",
            store.user_interaction_count(anon),
            is_complete=False,
            stop_reason="refetch_requested",
        )

    items = store.user_interaction_count(anon)
    allowed_types = {
        weights.COLLECTION_TYPE_ID[type_name]
        for type_name in cfg.interactions.collection_types
    }
    checkpoint_key = f"collections:{anon}:all"
    refetch_marker_key = f"collections:{anon}:refetch_marker"
    if refetch:
        # All pages in this logical refetch share one marker, including pages
        # resumed in a later invocation. Once complete, rows with an older
        # marker can be removed without discarding the previous snapshot early.
        refetch_marker = _utcnow()
        store.set_checkpoint(refetch_marker_key, refetch_marker)
    else:
        refetch_marker = store.get_checkpoint(refetch_marker_key)
    offset = int(store.get_checkpoint(checkpoint_key) or 0)
    pages_this_run = 0
    pages_total = int(previous["pages_fetched"] if previous else 0)
    total_reported = previous["total_reported"] if previous else None
    while True:
        if (
            cfg.interactions.max_pages_per_run
            and pages_this_run >= cfg.interactions.max_pages_per_run
        ):
            store.set_seed_user(
                username,
                anon,
                "truncated",
                items,
                pages_fetched=pages_total,
                next_offset=offset,
                total_reported=total_reported,
                is_complete=False,
                stop_reason="run_page_limit",
            )
            return username, "truncated", None
        try:
            page = bangumi.fetch_user_collections_page(
                client, username, None, offset, cfg.interactions.page_size
            )
        except http_client.HttpError as exc:
            if exc.status in (403, 404):
                # Already recorded once by the client's on_failure callback
                # (username-masked); a second entry here would double-log.
                store.set_seed_user(
                    username,
                    anon,
                    "unavailable",
                    items,
                    pages_fetched=pages_total,
                    next_offset=offset,
                    total_reported=total_reported,
                    is_complete=False,
                    stop_reason=f"http_{exc.status}",
                    last_error=str(exc),
                )
                return username, "unavailable", str(exc)
            store.set_seed_user(
                username,
                anon,
                "error",
                items,
                pages_fetched=pages_total,
                next_offset=offset,
                total_reported=total_reported,
                is_complete=False,
                stop_reason="http_error",
                last_error=str(exc),
            )
            return username, "error", str(exc)
        except ValueError as exc:
            fail_log.append({
                "ts": _utcnow(), "stage": "interactions",
                "url": f"/v0/users/***/collections", "status": None,
                "message": f"invalid collection response: {exc}",
                "retries": 0, "task": "user_collection",
            })
            store.set_seed_user(
                username,
                anon,
                "error",
                items,
                pages_fetched=pages_total,
                next_offset=offset,
                total_reported=total_reported,
                is_complete=False,
                stop_reason="invalid_response",
                last_error=str(exc),
            )
            return username, "error", str(exc)

        now = refetch_marker or _utcnow()
        fetched = 0
        received = len(page.data)
        for item in page.data:
            if item.subject_id is None or item.type not in allowed_types:
                continue
            actual_type = int(item.type)
            store.upsert_interaction({
                "anon_user_id": anon,
                "subject_id": item.subject_id,
                "collection_type": actual_type,
                "collection_type_name": weights.COLLECTION_TYPE_NAME[actual_type],
                "user_rating": int(item.rate or 0),
                "updated_at": item.updated_at,
                "fetched_at": now,
            })
            fetched += 1
        pages_this_run += 1
        pages_total += 1
        new_offset = offset + received
        if page.total is not None:
            total_reported = int(page.total)
        store.set_checkpoint(checkpoint_key, str(new_offset))
        items = store.user_interaction_count(anon)
        if received == 0 or (page.total is not None and new_offset >= page.total):
            if refetch_marker:
                store.prune_user_interactions(anon, refetch_marker)
                store.clear_checkpoints(refetch_marker_key)
                items = store.user_interaction_count(anon)
            final_status = "complete" if items > 0 else "empty"
            store.set_seed_user(
                username,
                anon,
                final_status,
                items,
                pages_fetched=pages_total,
                next_offset=new_offset,
                total_reported=total_reported,
                is_complete=True,
                stop_reason="end_of_stream",
            )
            return username, "success", None
        store.set_seed_user(
            username,
            anon,
            "pending",
            items,
            pages_fetched=pages_total,
            next_offset=new_offset,
            total_reported=total_reported,
            is_complete=False,
            stop_reason="page_checkpoint",
        )
        offset = new_offset


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Collect public user-anime interactions via seed users"
    )
    parser.add_argument("--config", default="dataset_config.json", help="JSON config file")
    parser.add_argument("--users", default="", help="path to seed_users.txt "
                        "(default: <config_dir>/seed_users.txt)")
    parser.add_argument("--refetch", action="store_true",
                        help="reset checkpoints so all seed users are re-fetched "
                        "(upserts keep the table duplicate-free)")
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="after priority sorting, process at most this many users",
    )
    parser.add_argument(
        "--new-users-first",
        action="store_true",
        help="prioritize seed users not yet present in the checkpoint database",
    )
    args = parser.parse_args()
    if args.limit < 0:
        parser.error("--limit must be >= 0")

    cfg = load_config(args.config)
    store = db.Store(cfg.checkpoint_db)
    fail_log = FailLog(cfg.failed_requests)
    client = http_client.BangumiHttpClient(cfg.api, stage="interactions",
                                           on_failure=fail_log.append)
    salt = anon_id.load_or_create_salt(cfg.salt_path)

    users_path = cfg.resolve(args.users) if args.users else cfg.seed_users_path
    users = prioritize_seed_users(
        store,
        salt,
        read_seed_users(users_path),
        new_users_first=args.new_users_first,
    )
    user_limit = args.limit or cfg.interactions.dry_run_max_users
    if user_limit > 0:
        users = users[:user_limit]
        print(
            f"[limit] prioritized seed users limited to {len(users)}"
        )

    if not users:
        print(f"[interactions] no seed users found in {users_path}", file=sys.stderr)
        store.close()
        return 1

    run_id = store.start_run("interactions")
    started = time.time()
    counts = {
        "success": 0,
        "truncated": 0,
        "failed": 0,
        "skipped": 0,
        "unavailable": 0,
    }
    print(f"[interactions] {len(users)} seed users x 1 combined collection stream "
          f"({len(cfg.interactions.collection_types)} accepted types)")

    def wrapped(user: str):
        return work_user(cfg, store, client, fail_log, salt, user, args.refetch)

    try:
        with ThreadPoolExecutor(max_workers=cfg.api.max_concurrency) as pool:
            futures = [pool.submit(wrapped, user) for user in users]
            for processed, future in enumerate(as_completed(futures), start=1):
                _, status, _ = future.result()
                if status == "success":
                    counts["success"] += 1
                elif status == "truncated":
                    counts["truncated"] += 1
                elif status == "skipped":
                    counts["skipped"] += 1
                elif status == "unavailable":
                    counts["unavailable"] += 1
                else:
                    counts["failed"] += 1
                if processed % 50 == 0 or processed == len(users):
                    print(
                        f"[interactions] progress={processed}/{len(users)} "
                        f"complete={counts['success']} truncated={counts['truncated']} "
                        f"failed={counts['failed']} skipped={counts['skipped']}",
                        flush=True,
                    )
    except KeyboardInterrupt:
        print("\n[interactions] interrupted by user; checkpoints saved - rerun to continue",
              file=sys.stderr)
        store.finish_run(run_id, {**counts, "retries": client.stats.retries,
                                  "cursor": "interrupted"})
        store.close()
        return 130

    store.finish_run(run_id, {**counts, "retries": client.stats.retries,
                              "cursor": f"users={len(users)}"})
    stats = client.stats.snapshot()
    elapsed = time.time() - started
    print(f"[interactions] done in {elapsed:.1f}s | success={counts['success']} "
          f"truncated={counts['truncated']} "
          f"failed={counts['failed']} skipped={counts['skipped']} "
          f"unavailable={counts['unavailable']} "
          f"http_requests={stats['success']} retries={stats['retries']} "
          f"requests_failed={stats['failed']}")
    print(f"[interactions] db rows={store.interaction_count()} | "
          f"salt kept at {cfg.salt_path} (never exported)")
    store.close()
    return 0 if counts["failed"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
