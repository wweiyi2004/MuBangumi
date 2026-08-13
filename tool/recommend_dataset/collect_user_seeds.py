#!/usr/bin/env python3
"""Discover public Bangumi community authors for a local research seed list."""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from src import http_client, user_seeds
from src.config import load_config

PUBLIC_P1_BASE_URL = "https://next.bgm.tv"


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def append_failure(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    safe_record = {
        "ts": record.get("ts"),
        "stage": "user_seeds",
        "url": record.get("url"),
        "params": record.get("params"),
        "status": record.get("status"),
        "message": record.get("message"),
        "retries": record.get("retries", 0),
    }
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(safe_record, ensure_ascii=False) + "\n")


def is_access_challenge(error: http_client.HttpError) -> bool:
    if error.status in (401, 403):
        return True
    response = error.response_head.casefold()
    return "cloudflare" in response or "turnstile" in response or "captcha" in response


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Discover public community authors into a local seed-user file"
    )
    parser.add_argument("--config", default="dataset_config.json", help="JSON config file")
    parser.add_argument("--target-users", type=positive_int, default=600)
    parser.add_argument("--max-topic-pages", type=positive_int, default=20)
    parser.add_argument("--max-topics", type=positive_int, default=400)
    parser.add_argument("--page-size", type=positive_int, default=50)
    parser.add_argument("--base-users", default="seed_users.txt")
    parser.add_argument("--output", default="seed_users_stage2.txt")
    parser.add_argument("--state", default="data/user_seed_discovery.json")
    parser.add_argument("--reset-progress", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.page_size > 50:
        parser.error("--page-size must not exceed 50")

    cfg = load_config(args.config)
    base_path = cfg.resolve(args.base_users)
    output_path = cfg.resolve(args.output)
    state_path = cfg.resolve(args.state)
    failure_path = cfg.data_dir / "user_seed_failures.jsonl"
    usernames = user_seeds.read_usernames(base_path)
    usernames.update(user_seeds.read_usernames(output_path))
    state = user_seeds.DiscoveryState() if args.reset_progress else (
        user_seeds.DiscoveryState.load(state_path)
    )

    print(
        f"[user-seeds] existing={len(usernames)} target={args.target_users} "
        f"offset={state.next_offset} seen_topics={len(state.seen_topic_ids)}"
    )
    if args.dry_run:
        print("[user-seeds] dry-run: no network requests and no files changed")
        return 0

    api = cfg.api.model_copy(
        update={
            "base_url": PUBLIC_P1_BASE_URL,
            "qps": min(cfg.api.qps, 1.0),
            "max_concurrency": 1,
        }
    )
    client = http_client.BangumiHttpClient(
        api,
        stage="user_seeds",
        on_failure=lambda record: append_failure(failure_path, record),
    )

    checkpoint_count = 0

    def checkpoint(current_users: set[str], current_state: user_seeds.DiscoveryState) -> None:
        nonlocal checkpoint_count
        user_seeds.write_usernames(output_path, current_users)
        current_state.save(state_path)
        checkpoint_count += 1
        if checkpoint_count % 25 == 0:
            print(
                f"[user-seeds] users={len(current_users)} "
                f"seen_topics={len(current_state.seen_topic_ids)}",
                flush=True,
            )

    try:
        result = user_seeds.discover_usernames(
            client,
            usernames,
            state,
            target_users=args.target_users,
            max_topic_pages=args.max_topic_pages,
            max_topics=args.max_topics,
            page_size=args.page_size,
            checkpoint=checkpoint,
        )
    except KeyboardInterrupt:
        checkpoint(usernames, state)
        print("[user-seeds] interrupted; local checkpoint saved", file=sys.stderr)
        return 130
    except http_client.HttpError as exc:
        checkpoint(usernames, state)
        if is_access_challenge(exc):
            print(
                "[user-seeds] access challenge/refusal detected; stopped without bypass",
                file=sys.stderr,
            )
            return 2
        print(f"[user-seeds] request failed: {exc}", file=sys.stderr)
        return 1
    except (ValueError, json.JSONDecodeError) as exc:
        checkpoint(usernames, state)
        print(f"[user-seeds] response/state error: {exc}", file=sys.stderr)
        return 1

    checkpoint(result.users, state)
    stats = client.stats.snapshot()
    generated_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    print(
        f"[user-seeds] done users={len(result.users)} new={result.new_users} "
        f"topic_pages={result.list_pages} topic_details={result.topic_details} "
        f"unavailable_topics={result.unavailable_topics} "
        f"http_requests={stats['success']} retries={stats['retries']} "
        f"generated_at={generated_at}"
    )
    print(f"[user-seeds] local output: {output_path}")
    if len(result.users) < args.target_users:
        reason = "source exhausted" if result.exhausted else "run limit reached"
        print(
            f"[user-seeds] target not reached ({reason}); rerun or raise safe limits",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
