#!/usr/bin/env python3
"""Phase 1a: collect anime subjects from the Bangumi public API.

Enumeration sources (all official public API, no HTML scraping):
  - calendar endpoint (currently airing titles)
  - quarterly search (empty keyword + air_date filter), paginated
  - explicit seed_subject_ids from the config

Resume: subject rows carry a per-id status; already-ok subjects are skipped on
re-runs, failed ones are retried. Search pagination resumes from its stored
offset checkpoint. All request failures are appended to failed_requests.jsonl.

Usage:
  python tool/recommend_dataset/collect_subjects.py --config dataset_config.json
"""
from __future__ import annotations

import argparse
import json
import sys
import threading
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from src import bangumi, db, http_client, parse, splits, weights
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
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _json_or_none(value: object) -> str | None:
    """JSON-encode a list/dict, or None when empty (keeps coverage honest)."""
    if value in (None, [], {}):
        return None
    return json.dumps(value, ensure_ascii=False)


def enumerate_subject_ids(cfg, client, store, fail_log) -> list[int]:
    """Build the candidate id list from all configured enumeration sources."""
    ids: set[int] = set(cfg.subjects.seed_subject_ids)

    if cfg.subjects.use_calendar:
        try:
            days = bangumi.fetch_calendar(client)
            for day in days:
                for item in day.items:
                    if item.type == bangumi.SUBJECT_TYPE_ANIME:
                        ids.add(item.id)
        except http_client.HttpError as exc:
            fail_log.append({
                "ts": _utcnow(), "stage": "subjects", "url": "/calendar",
                "status": exc.status, "message": f"calendar enumeration failed: {exc}",
                "retries": exc.retries, "task": "enumeration:calendar",
            })
            print(f"  [warn] calendar enumeration failed: {exc}", file=sys.stderr)

    for year, quarter in cfg.subjects.year_quarters:
        key = f"search:{year}:{quarter}"
        offset = int(store.get_checkpoint(key) or 0)
        max_offset = cfg.subjects.max_offset_per_query
        while offset <= max_offset:
            try:
                page = bangumi.search_page(client, year, quarter, offset)
            except http_client.HttpError as exc:
                fail_log.append({
                    "ts": _utcnow(), "stage": "subjects", "url": "/v0/search/subjects",
                    "status": exc.status, "message": f"search {year}Q{quarter} offset={offset} failed: {exc}",
                    "retries": exc.retries, "task": f"enumeration:search:{year}:{quarter}@{offset}",
                })
                print(f"  [warn] search {year}Q{quarter} offset={offset} failed: {exc}",
                      file=sys.stderr)
                break  # checkpoint stays at the failing offset; next run retries from here
            except ValueError as exc:
                fail_log.append({
                    "ts": _utcnow(), "stage": "subjects", "url": "/v0/search/subjects",
                    "status": None, "message": f"invalid search response: {exc}",
                    "retries": 0, "task": f"enumeration:search:{year}:{quarter}@{offset}",
                })
                print(f"  [warn] invalid search response at {year}Q{quarter} offset={offset}: {exc}",
                      file=sys.stderr)
                break
            for item in page.data:
                ids.add(item.id)
            new_offset = offset + len(page.data)
            store.set_checkpoint(key, str(new_offset))
            if (
                not page.data
                or (page.total is not None and new_offset >= page.total)
                or len(page.data) < page.limit
            ):
                break
            offset = new_offset
    return sorted(ids)


def plan_backfill(store, failed_only: bool = False) -> dict:
    """Plan the --from-interactions backfill task list.

    Returns aggregate counts plus ``tasks``. Normal mode includes never-seen,
    pending and failed references so a process interruption is genuinely
    resumable. ``failed_only`` restricts the queue to failed rows.
    """
    referenced = store.list_interaction_subject_ids()
    existing = store.subject_count(statuses=("ok",))
    missing = store.list_missing_interaction_subject_ids()
    retryable = store.list_retryable_interaction_subject_ids()
    known_non_anime = store.list_known_non_anime_ids()
    if failed_only:
        # A failed id necessarily has a subjects row (it was claimed), so it is
        # never in `missing`; the failed-only source is the failed status itself.
        tasks = [
            sid for sid in store.list_failed_interaction_subject_ids()
            if sid not in known_non_anime
        ]
    else:
        tasks = sorted(
            (set(missing) | set(retryable)) - known_non_anime
        )
    return {
        "referenced": len(referenced),
        "existing": existing,
        "missing": len(missing),
        "retryable": len(retryable),
        "known_non_anime": len(known_non_anime),
        "tasks": tasks,
    }


def plan_value_backfill(store, cfg) -> dict:
    """Rank missing metadata by offline-training and evaluation value.

    Validation/test references are ranked first, then regular/strong train
    support, then total positive support.  The returned report is aggregate;
    no per-user information is emitted.
    """
    base = plan_backfill(store)
    candidate_ids = set(base["tasks"])
    evaluation_counts: Counter[int] = Counter()
    regular_train_counts: Counter[int] = Counter()
    strong_counts: Counter[int] = Counter()
    positive_counts: Counter[int] = Counter()

    for row in store.list_interactions():
        subject_id = int(row["subject_id"])
        if subject_id not in candidate_ids:
            continue
        collection_type = int(row.get("collection_type") or 0)
        rating = int(row.get("user_rating") or 0)
        tier = weights.feedback_tier(collection_type, rating)
        if tier == weights.FEEDBACK_NEGATIVE:
            continue
        split, _ = splits.interaction_split(
            row.get("updated_at"), None, cfg.splits.train_end_date
        )
        positive_counts[subject_id] += 1
        if tier == weights.FEEDBACK_STRONG:
            strong_counts[subject_id] += 1
        if split in (splits.SPLIT_VALIDATION, splits.SPLIT_TEST):
            evaluation_counts[subject_id] += 1
        elif split == splits.SPLIT_TRAIN and tier in (
            weights.FEEDBACK_STRONG,
            weights.FEEDBACK_REGULAR,
        ):
            regular_train_counts[subject_id] += 1

    tasks = sorted(
        candidate_ids,
        key=lambda subject_id: (
            -int(evaluation_counts[subject_id] > 0),
            -evaluation_counts[subject_id],
            -regular_train_counts[subject_id],
            -strong_counts[subject_id],
            -positive_counts[subject_id],
            subject_id,
        ),
    )
    return {
        **base,
        "tasks": tasks,
        "priority": "evaluation_then_regular_train_support",
        "evaluation_candidates": sum(
            evaluation_counts[subject_id] > 0 for subject_id in candidate_ids
        ),
        "regular_train_candidates": sum(
            regular_train_counts[subject_id] > 0 for subject_id in candidate_ids
        ),
        "weak_or_unassigned_only": sum(
            evaluation_counts[subject_id] == 0
            and regular_train_counts[subject_id] == 0
            for subject_id in candidate_ids
        ),
    }


def plan_cold_eval_backfill(store, cfg) -> dict:
    """Prioritize metadata missing from cold validation/test interactions."""
    subjects = store.list_subjects(statuses=("ok",))
    content_ids = {int(row["subject_id"]) for row in subjects}
    air_dates = {int(row["subject_id"]): row.get("air_date") for row in subjects}
    train_ids: set[int] = set()
    validation_counts: Counter[int] = Counter()
    test_counts: Counter[int] = Counter()

    for row in store.list_interactions():
        collection_type = int(row.get("collection_type") or 0)
        rating = int(row.get("user_rating") or 0)
        if weights.is_negative_feedback(collection_type, rating):
            continue
        subject_id = int(row["subject_id"])
        split, _ = splits.interaction_split(
            row.get("updated_at"), air_dates.get(subject_id), cfg.splits.train_end_date
        )
        if split == splits.SPLIT_TRAIN:
            train_ids.add(subject_id)
        elif split == splits.SPLIT_VALIDATION:
            validation_counts[subject_id] += 1
        elif split == splits.SPLIT_TEST:
            test_counts[subject_id] += 1

    blocked_ids = store.list_blocked_interaction_subject_ids()
    cold_validation = {
        subject_id for subject_id in validation_counts
        if subject_id not in train_ids and subject_id not in blocked_ids
    }
    cold_test = {
        subject_id for subject_id in test_counts
        if subject_id not in train_ids and subject_id not in blocked_ids
    }
    missing_validation = cold_validation - content_ids
    missing_test = cold_test - content_ids
    validation_ranked = sorted(
        missing_validation, key=lambda subject_id: (-validation_counts[subject_id], subject_id)
    )
    test_ranked = sorted(
        missing_test, key=lambda subject_id: (-test_counts[subject_id], subject_id)
    )
    tasks: list[int] = []
    seen: set[int] = set()
    for index in range(max(len(validation_ranked), len(test_ranked))):
        for ranked in (validation_ranked, test_ranked):
            if index < len(ranked) and ranked[index] not in seen:
                seen.add(ranked[index])
                tasks.append(ranked[index])
    tasks = store.subjects_needing_fetch(tasks)
    return {
        "cold_validation": len(cold_validation),
        "cold_test": len(cold_test),
        "content_cold_validation": len(cold_validation & content_ids),
        "content_cold_test": len(cold_test & content_ids),
        "missing_validation": len(missing_validation),
        "missing_test": len(missing_test),
        "tasks": tasks,
    }


def build_subject_record(cfg, client, fail_log, detail: bangumi.SubjectDetail) -> dict:
    """Normalize a validated subject detail into a DB record.

    Optional enrichment requests (characters / related / persons) are
    best-effort: a failing sub-request is logged and leaves the field empty
    instead of blocking the whole subject.
    """
    year, month, _ = parse.parse_date_parts(detail.date)
    infobox = parse.parse_infobox(detail.infobox)
    features = parse.extract_cold_start_features(infobox)
    collection = detail.collection

    def _count(name: str):
        return getattr(collection, name, None) if collection else None

    collection_total = None
    if collection:
        parts = [collection.wish, collection.collect, collection.doing,
                 collection.on_hold, collection.dropped]
        if any(p is not None for p in parts):
            collection_total = sum(p or 0 for p in parts)

    record = {
        "subject_id": detail.id,
        "name": detail.name,
        "name_cn": detail.name_cn,
        "air_date": detail.date,
        "year": year,
        "season": parse.season_of_month(month),
        "platform": detail.platform,
        "episode_count": detail.total_episodes,
        "summary": detail.summary,
        "tags_json": _json_or_none(parse.tag_names(detail.tags)),
        "meta_tags_json": _json_or_none(parse.clean_meta_tags(detail.meta_tags)),
        "infobox_json": _json_or_none(infobox),
        "score": detail.rating.score if detail.rating else None,
        "rank": detail.rating.rank if detail.rating else None,
        "rating_total": detail.rating.total if detail.rating else None,
        "collection_total": collection_total,
        "wish_count": _count("wish"),
        "doing_count": _count("doing"),
        "collect_count": _count("collect"),
        "on_hold_count": _count("on_hold"),
        "dropped_count": _count("dropped"),
        "image_url": parse.image_url_of(detail.images),
        "nsfw": bool(detail.nsfw),
        "production_json": _json_or_none(features.get("production")),
        "director_json": _json_or_none(features.get("director")),
        "series_composer_json": _json_or_none(features.get("series_composer")),
        "original_work_json": _json_or_none(features.get("original_work")),
        "music_json": _json_or_none(features.get("music")),
        "fetched_at": _utcnow(),
    }

    if cfg.subjects.fetch_characters:
        try:
            chars = bangumi.fetch_characters(client, detail.id)
            record["voice_actors_json"] = _json_or_none(parse.voice_actor_names(chars))
        except (http_client.HttpError, ValueError) as exc:
            fail_log.append({
                "ts": _utcnow(), "stage": "subjects",
                "url": f"/v0/subjects/{detail.id}/characters",
                "status": exc.status if isinstance(exc, http_client.HttpError) else None,
                "message": f"characters enrichment failed, field left empty: {exc}",
                "retries": getattr(exc, "retries", 0), "task": f"subject:{detail.id}:characters",
            })
    if cfg.subjects.fetch_related:
        try:
            related = bangumi.fetch_related(client, detail.id)
            record["related_json"] = _json_or_none(parse.related_entries(related))
        except (http_client.HttpError, ValueError) as exc:
            fail_log.append({
                "ts": _utcnow(), "stage": "subjects",
                "url": f"/v0/subjects/{detail.id}/subjects",
                "status": exc.status if isinstance(exc, http_client.HttpError) else None,
                "message": f"related enrichment failed, field left empty: {exc}",
                "retries": getattr(exc, "retries", 0), "task": f"subject:{detail.id}:related",
            })
    if cfg.subjects.fetch_persons:
        try:
            persons = bangumi.fetch_persons(client, detail.id)
            record["persons_json"] = _json_or_none(persons)
        except (http_client.HttpError, ValueError) as exc:
            fail_log.append({
                "ts": _utcnow(), "stage": "subjects",
                "url": f"/v0/subjects/{detail.id}/persons",
                "status": exc.status if isinstance(exc, http_client.HttpError) else None,
                "message": f"persons enrichment failed, field left empty: {exc}",
                "retries": getattr(exc, "retries", 0), "task": f"subject:{detail.id}:persons",
            })
    return record


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect anime subjects from the Bangumi API")
    parser.add_argument("--config", default="dataset_config.json", help="JSON config file")
    parser.add_argument("--from-interactions", action="store_true",
                        help="backfill: fetch subjects referenced by interactions but missing "
                             "from the subjects table")
    parser.add_argument("--limit", type=int, default=0,
                        help="with --from-interactions: cap the number of backfill fetches")
    parser.add_argument("--dry-run", action="store_true",
                        help="with --from-interactions: only report what would be fetched, "
                             "make no requests")
    parser.add_argument("--failed-only", action="store_true",
                        help="with --from-interactions: only retry previously failed subjects")
    parser.add_argument(
        "--priority",
        choices=("value", "subject-id"),
        default="value",
        help="with --from-interactions: order missing metadata by model value "
             "(default) or numeric subject id",
    )
    parser.add_argument("--cold-eval", action="store_true",
                        help="with --from-interactions: prioritize metadata for cold "
                             "validation/test items instead of all missing references")
    parser.add_argument("--metadata-only", action="store_true",
                        help="fetch subject detail only; skip characters, related and persons")
    args = parser.parse_args()
    if args.cold_eval and not args.from_interactions:
        parser.error("--cold-eval requires --from-interactions")

    cfg = load_config(args.config)
    if args.metadata_only:
        cfg.subjects.fetch_characters = False
        cfg.subjects.fetch_related = False
        cfg.subjects.fetch_persons = False
    store = db.Store(cfg.checkpoint_db)
    fail_log = FailLog(cfg.failed_requests)
    client = http_client.BangumiHttpClient(cfg.api, stage="subjects", on_failure=fail_log.append)
    run_id = store.start_run("subjects")
    started = time.time()
    counts = {"success": 0, "failed": 0, "skipped": 0, "non_anime": 0, "not_found": 0}

    def work(subject_id: int) -> tuple[int, str, str | None]:
        try:
            detail = bangumi.fetch_subject(client, subject_id)
        except http_client.HttpError as exc:
            # Already logged via the client's on_failure callback.
            status = "permanent" if exc.is_permanent() else "failed"
            store.mark_subject_status(subject_id, status, str(exc))
            return subject_id, status, str(exc)
        except ValueError as exc:
            fail_log.append({
                "ts": _utcnow(), "stage": "subjects", "url": f"/v0/subjects/{subject_id}",
                "status": None, "message": f"response validation failed: {exc}",
                "retries": 0, "task": f"subject:{subject_id}",
            })
            store.mark_subject_status(subject_id, "failed", str(exc))
            return subject_id, "failed", str(exc)
        if detail.type != bangumi.SUBJECT_TYPE_ANIME:
            # Not anime: never write into the anime subjects table. Remember the
            # id as non-anime so it is not requested again on the next backfill.
            store.delete_subject(subject_id)
            store.record_known_subject(subject_id, detail.type, detail.name)
            return subject_id, "non_anime", f"type={detail.type}"
        try:
            record = build_subject_record(cfg, client, fail_log, detail)
        except (http_client.HttpError, ValueError) as exc:
            fail_log.append({
                "ts": _utcnow(), "stage": "subjects", "url": f"/v0/subjects/{subject_id}",
                "status": getattr(exc, "status", None),
                "message": f"record build failed: {exc}",
                "retries": getattr(exc, "retries", 0), "task": f"subject:{subject_id}",
            })
            store.mark_subject_status(subject_id, "failed", str(exc))
            return subject_id, "failed", str(exc)
        store.upsert_subject(record)
        store.mark_subject_status(subject_id, "ok")
        return subject_id, "success", None

    def run_tasks(tasks: list[int], label: str) -> None:
        if not tasks:
            print(f"[subjects] {label}: nothing to fetch")
            return
        with ThreadPoolExecutor(max_workers=cfg.api.max_concurrency) as pool:
            futures = {pool.submit(work, sid): sid for sid in tasks}
            for future in as_completed(futures):
                _, status, _ = future.result()
                if status == "success":
                    counts["success"] += 1
                elif status == "non_anime":
                    counts["non_anime"] += 1
                elif status == "permanent":
                    counts["not_found"] += 1
                else:
                    counts["failed"] += 1

    cursor_text = "enumerated=0"
    try:
        if args.from_interactions:
            # Backfill mode: fetch interaction-referenced subjects we never fetched.
            plan = (
                plan_cold_eval_backfill(store, cfg)
                if args.cold_eval
                else (
                    plan_backfill(store, failed_only=True)
                    if args.failed_only
                    else (
                        plan_value_backfill(store, cfg)
                        if args.priority == "value"
                        else plan_backfill(store)
                    )
                )
            )
            tasks = plan["tasks"]
            if args.cold_eval:
                counts["skipped"] = (
                    plan["cold_validation"] + plan["cold_test"] - len(tasks)
                )
                print(
                    f"[cold-eval] cold_validation={plan['cold_validation']} "
                    f"cold_test={plan['cold_test']} "
                    f"content_validation={plan['content_cold_validation']} "
                    f"content_test={plan['content_cold_test']} "
                    f"missing_validation={plan['missing_validation']} "
                    f"missing_test={plan['missing_test']} to_fetch={len(tasks)}"
                )
            else:
                counts["skipped"] = plan["referenced"] - len(tasks)
                print(f"[backfill] referenced={plan['referenced']} existing={plan['existing']} "
                      f"missing={plan['missing']} retryable={plan['retryable']} "
                      f"known_non_anime={plan['known_non_anime']} "
                      f"to_fetch={len(tasks)}")
                if plan.get("priority"):
                    print(
                        f"[backfill] priority={plan['priority']} "
                        f"evaluation_candidates={plan['evaluation_candidates']} "
                        f"regular_train_candidates={plan['regular_train_candidates']} "
                        f"weak_or_unassigned_only={plan['weak_or_unassigned_only']}"
                    )
            if args.limit > 0:
                tasks = tasks[: args.limit]
                print(f"[backfill] --limit active: at most {len(tasks)} to fetch this run")
            if args.dry_run:
                print("[backfill] dry-run: no requests issued")
                store.finish_run(run_id, {**counts, "retries": 0,
                                          "cursor": f"backfill_dry_run={len(tasks)}"})
                store.close()
                return 0
            # Claim every task as a pending row first: the rows themselves are the
            # resume state, so an interruption never re-fetches from scratch.
            for sid in tasks:
                store.claim_subject(sid)
            run_tasks(tasks, "backfill")
            cursor_text = f"backfill={len(tasks)}"
        else:
            ids = enumerate_subject_ids(cfg, client, store, fail_log)
            tasks = store.subjects_needing_fetch(ids)
            counts["skipped"] = len(ids) - len(tasks)
            if cfg.subjects.dry_run_max_subjects > 0:
                tasks = tasks[: cfg.subjects.dry_run_max_subjects]
                print(f"[dry-run] subject limit active: at most {len(tasks)} to fetch this run")
            print(f"[subjects] enumerated {len(ids)} unique ids, {counts['skipped']} "
                  f"already done, {len(tasks)} to fetch")
            run_tasks(tasks, "subjects")
            cursor_text = f"enumerated={len(ids)}"
    except KeyboardInterrupt:
        print("\n[subjects] interrupted by user; state saved - rerun to continue", file=sys.stderr)
        store.finish_run(run_id, {**counts, "retries": client.stats.retries,
                                  "cursor": "interrupted"})
        store.close()
        return 130

    store.finish_run(run_id, {**counts, "retries": client.stats.retries, "cursor": cursor_text})
    stats = client.stats.snapshot()
    elapsed = time.time() - started
    print(f"[subjects] done in {elapsed:.1f}s | success={counts['success']} "
          f"failed={counts['failed']} skipped={counts['skipped']} "
          f"non_anime={counts['non_anime']} not_found={counts['not_found']} "
          f"http_requests={stats['success']} retries={stats['retries']} "
          f"requests_failed={stats['failed']}")
    print(f"[subjects] db rows(ok)={store.subject_count(statuses=('ok',))} | "
          f"failures logged to {cfg.failed_requests}")
    store.close()
    return 0 if counts["failed"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
