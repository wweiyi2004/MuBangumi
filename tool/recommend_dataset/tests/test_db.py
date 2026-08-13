"""SQLite store: upsert dedup, checkpoints, resume helpers, run stats."""
from __future__ import annotations

import sqlite3

from src import db


def _subject(sid: int, **overrides) -> dict:
    record = {
        "subject_id": sid,
        "name": f"条目{sid}",
        "air_date": "2026-01-01",
        "year": 2026,
        "season": 1,
        "fetched_at": "2026-01-01T00:00:00Z",
    }
    record.update(overrides)
    return record


def test_upsert_subject_dedup(store):
    assert store.upsert_subject(_subject(1)) == "inserted"
    assert store.upsert_subject(_subject(1, name="改名")) == "updated"
    assert store.upsert_subject(_subject(1, name="改名")) == "updated"
    assert store.subject_count() == 1
    assert store.meta_value("subjects_inserted") == 1
    assert store.meta_value("subjects_updated") == 2


def test_upsert_subject_refreshes_fields(store):
    store.upsert_subject(_subject(1, name="旧名"))
    store.upsert_subject(_subject(1, name="新名", platform="WEB"))
    rows = store.list_subjects()
    assert rows[0]["name"] == "新名"
    assert rows[0]["platform"] == "WEB"


def test_upsert_interaction_dedup(store):
    row = {
        "anon_user_id": "a" * 64,
        "subject_id": 1,
        "collection_type": 1,
        "collection_type_name": "wish",
        "user_rating": 7,
        "updated_at": "2025-01-01T00:00:00+08:00",
        "fetched_at": "2026-01-01T00:00:00Z",
    }
    assert store.upsert_interaction(row) == "inserted"
    assert store.upsert_interaction({**row, "user_rating": 8}) == "updated"
    assert store.interaction_count() == 1
    assert store.meta_value("interactions_inserted") == 1
    assert store.meta_value("interactions_updated") == 1
    rows = store.list_interactions()
    assert rows[0]["user_rating"] == 8


def test_prune_user_interactions_keeps_only_current_snapshot(store):
    base = {
        "anon_user_id": "a" * 64,
        "collection_type": 1,
        "collection_type_name": "wish",
        "user_rating": 0,
        "updated_at": "2025-01-01T00:00:00Z",
    }
    store.upsert_interaction({**base, "subject_id": 1, "fetched_at": "old"})
    store.upsert_interaction({**base, "subject_id": 2, "fetched_at": "current"})
    store.upsert_interaction({
        **base,
        "anon_user_id": "b" * 64,
        "subject_id": 3,
        "fetched_at": "old",
    })

    assert store.prune_user_interactions("a" * 64, "current") == 1
    assert {(row["anon_user_id"], row["subject_id"]) for row in store.list_interactions()} == {
        ("a" * 64, 2),
        ("b" * 64, 3),
    }


def test_checkpoint_roundtrip(store):
    assert store.get_checkpoint("collections:x:1") is None
    store.set_checkpoint("collections:x:1", "100")
    assert store.get_checkpoint("collections:x:1") == "100"
    store.set_checkpoint("collections:x:1", "200")
    assert store.get_checkpoint("collections:x:1") == "200"


def test_clear_checkpoints_by_prefix(store):
    store.set_checkpoint("collections:aaa:1", "10")
    store.set_checkpoint("collections:aaa:2", "20")
    store.set_checkpoint("search:2026:1", "25")
    assert store.clear_checkpoints("collections:aaa:") == 2
    assert store.get_checkpoint("search:2026:1") == "25"
    assert store.get_checkpoint("collections:aaa:1") is None


def test_subjects_needing_fetch_resume(store):
    store.upsert_subject(_subject(1))
    store.upsert_subject(_subject(2))
    store.mark_subject_status(1, "ok")
    store.mark_subject_status(2, "failed", "HTTP 500")
    store.upsert_subject(_subject(3))
    store.mark_subject_status(3, "permanent", "HTTP 404")
    store.upsert_subject(_subject(4))

    need = store.subjects_needing_fetch([1, 2, 3, 4, 99])
    assert need == [2, 4, 99]  # ok/permanent skipped; failed + fresh retried; unknown -> fetch


def test_run_stats_aggregate(store):
    run_a = store.start_run("subjects")
    store.finish_run(run_a, {"success": 5, "failed": 1, "skipped": 2, "retries": 3, "cursor": "x"})
    run_b = store.start_run("interactions")
    store.finish_run(run_b, {"success": 2, "failed": 0, "skipped": 0,
                             "truncated": 4, "retries": 0, "cursor": "y"})
    subjects = store.aggregate_stats("subjects")
    assert subjects["success"] == 5 and subjects["retries"] == 3 and subjects["runs"] == 1
    all_stats = store.aggregate_stats()
    assert all_stats["success"] == 7 and all_stats["runs"] == 2
    assert all_stats["truncated"] == 4


def test_seed_user_bookkeeping(store):
    assert store.seed_user_status("sai") is None
    store.set_seed_user("sai", "h" * 64, "complete", 169,
                        pages_fetched=2, next_offset=169,
                        total_reported=169, is_complete=True,
                        stop_reason="end_of_stream")
    assert store.seed_user_status("sai") == "complete"
    record = store.seed_user_record("sai")
    assert record["is_complete"] is True
    assert record["items_fetched"] == 169
    assert record["next_offset"] == 169
    store.set_seed_user("fenx", "i" * 64, "unavailable", 0)
    summary = store.seed_user_summary()
    assert summary["complete"] == 1 and summary["unavailable"] == 1


def test_legacy_seed_rows_migrate_without_claiming_ok_is_complete(tmp_path):
    path = tmp_path / "legacy.sqlite"
    conn = sqlite3.connect(path)
    conn.execute(
        "CREATE TABLE seed_users (username TEXT PRIMARY KEY, anon_user_id TEXT NOT NULL, "
        "status TEXT NOT NULL DEFAULT 'pending', items_fetched INTEGER NOT NULL DEFAULT 0, "
        "updated_at TEXT NOT NULL)"
    )
    conn.execute(
        "INSERT INTO seed_users VALUES('legacy-ok', ?, 'ok', 200, '2026-01-01')",
        ("a" * 64,),
    )
    conn.execute(
        "INSERT INTO seed_users VALUES('legacy-empty', ?, 'empty', 0, '2026-01-01')",
        ("b" * 64,),
    )
    conn.commit()
    conn.close()

    migrated = db.Store(path)
    assert migrated.seed_user_record("legacy-ok")["is_complete"] is False
    assert migrated.seed_user_record("legacy-empty")["is_complete"] is True
    migrated.close()


def test_reopen_store_preserves_data(tmp_path):
    path = tmp_path / "reopen.sqlite"
    first = db.Store(path)
    first.upsert_subject(_subject(1))
    first.set_checkpoint("k", "v")
    first.close()
    second = db.Store(path)
    assert second.subject_count() == 1
    assert second.get_checkpoint("k") == "v"
    second.close()
