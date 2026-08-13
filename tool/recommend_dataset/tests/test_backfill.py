"""--from-interactions backfill planning: diffs, resume, permanent 404s."""
from __future__ import annotations

from types import SimpleNamespace

from collect_subjects import (
    enumerate_subject_ids,
    plan_backfill,
    plan_cold_eval_backfill,
    plan_value_backfill,
)
from src import weights
from src.config import DatasetConfig


def _subject(sid: int, name: str = "条目") -> dict:
    return {"subject_id": sid, "name": name, "air_date": "2026-01-01",
            "fetched_at": "2026-01-01T00:00:00Z"}


def _interaction(anon: str, sid: int) -> dict:
    return {
        "anon_user_id": anon, "subject_id": sid,
        "collection_type": weights.COLLECTION_TYPE_ID["wish"],
        "collection_type_name": "wish",
        "user_rating": 0,
        "updated_at": "2025-06-01T00:00:00+08:00",
        "fetched_at": "2026-01-01T00:00:00Z",
    }


def test_search_enumeration_continues_when_total_missing():
    """A search response without 'total' must not truncate the enumeration
    after the first page; pagination continues until a short/empty page."""
    client = _SearchClientNoTotal([
        [{"id": sid} for sid in range(1, 26)],   # full page
        [{"id": sid} for sid in range(26, 36)],  # short page ends the stream
    ])
    cfg = SimpleNamespace(subjects=SimpleNamespace(
        seed_subject_ids=[],
        use_calendar=False,
        year_quarters=[[2026, 1]],
        max_offset_per_query=2000,
    ))

    class _CheckpointStore:
        def __init__(self):
            self.checkpoints = {}

        def get_checkpoint(self, key):
            return self.checkpoints.get(key)

        def set_checkpoint(self, key, value):
            self.checkpoints[key] = value

    class _FailLog:
        def append(self, record):
            raise AssertionError(record)

    ids = enumerate_subject_ids(cfg, client, _CheckpointStore(), _FailLog())
    assert ids == list(range(1, 36))


class _SearchClientNoTotal:
    """Search client whose pages omit 'total' (the API spec does not require it)."""

    def __init__(self, pages):
        self.pages = list(pages)

    def post_json(self, path, body):
        data = self.pages.pop(0) if self.pages else []
        return {"limit": 25, "offset": body.get("offset", 0), "data": data}


def test_missing_ids_are_difference(store):
    store.upsert_subject(_subject(1))
    store.mark_subject_status(1, "ok")
    for sid in (1, 2, 3):
        store.upsert_interaction(_interaction("a" * 64, sid))

    assert store.list_interaction_subject_ids() == [1, 2, 3]
    assert store.list_missing_interaction_subject_ids() == [2, 3]

    plan = plan_backfill(store)
    assert plan["referenced"] == 3
    assert plan["existing"] == 1
    assert plan["missing"] == 2
    assert plan["tasks"] == [2, 3]


def test_existing_subjects_not_refetched(store):
    """An already-ok subject never appears in the backfill task list."""
    store.upsert_subject(_subject(1))
    store.mark_subject_status(1, "ok")
    store.upsert_interaction(_interaction("a" * 64, 1))
    plan = plan_backfill(store)
    assert plan["tasks"] == []


def test_claim_placeholder_removes_from_missing(store):
    """Claiming a row IS the resume state: after a crash, claimed-but-unfinished
    subjects are no longer 'missing' and are not re-claimed from scratch."""
    store.upsert_interaction(_interaction("a" * 64, 7))
    assert store.list_missing_interaction_subject_ids() == [7]
    store.claim_subject(7)
    assert store.list_missing_interaction_subject_ids() == []
    assert store.subject_status(7) == "pending"
    assert store.subjects_needing_fetch([7]) == [7]  # pending -> still to fetch
    assert plan_backfill(store)["tasks"] == [7]


def test_permanent_404_not_retried(store):
    """404 -> permanent placeholder: excluded from failed-only and never missing."""
    store.upsert_interaction(_interaction("a" * 64, 9))
    store.claim_subject(9)
    store.mark_subject_status(9, "permanent", "HTTP 404")
    assert store.list_failed_interaction_subject_ids() == []
    assert store.list_missing_interaction_subject_ids() == []  # placeholder blocks retry
    assert store.subjects_needing_fetch([9]) == []
    plan = plan_backfill(store)
    assert plan["tasks"] == []


def test_failed_only_lists_only_failed(store):
    store.upsert_interaction(_interaction("a" * 64, 11))
    store.upsert_interaction(_interaction("a" * 64, 12))
    store.claim_subject(11)
    store.mark_subject_status(11, "failed", "boom")
    store.claim_subject(12)
    store.mark_subject_status(12, "ok")

    plan = plan_backfill(store, failed_only=True)
    assert plan["tasks"] == [11]
    plan_all = plan_backfill(store)
    assert plan_all["tasks"] == [11]  # failed rows remain resumable


def test_failed_then_ok_never_duplicates(store):
    """A failed subject is retried; on success the row is updated, not duplicated."""
    store.upsert_interaction(_interaction("a" * 64, 13))
    store.claim_subject(13)
    store.mark_subject_status(13, "failed", "HTTP 500")
    assert store.subject_count() == 1
    store.upsert_subject(_subject(13, "成功条目"))
    store.mark_subject_status(13, "ok")
    assert store.subject_count() == 1
    assert store.subject_status(13) == "ok"
    assert plan_backfill(store)["tasks"] == []


def test_non_anime_not_written_to_subjects(store):
    """Non-anime ids are remembered in known_subjects, never in the anime table."""
    store.upsert_interaction(_interaction("a" * 64, 20))
    store.claim_subject(20)
    store.delete_subject(20)
    store.record_known_subject(20, 1, "漫画")
    assert store.subject_count() == 0
    assert 20 in store.list_known_non_anime_ids()
    plan = plan_backfill(store)
    assert plan["known_non_anime"] == 1
    assert 20 not in plan["tasks"]


def test_limit_and_resume(store):
    """--limit caps a run; the next run continues with the rest (no duplicates)."""
    for sid in range(100, 110):
        store.upsert_interaction(_interaction("a" * 64, sid))
    plan = plan_backfill(store)
    assert plan["tasks"] == list(range(100, 110))

    first = plan["tasks"][:3]
    for sid in first:
        store.claim_subject(sid)
        store.upsert_subject(_subject(sid))
        store.mark_subject_status(sid, "ok")
    second = plan_backfill(store)["tasks"]
    assert second == list(range(103, 110))  # claimed ones are no longer missing
    assert not set(first) & set(second)


def test_cold_eval_backfill_prioritizes_missing_validation_and_test(store):
    train_end = DatasetConfig(splits={"train_end_date": "2025-12-31"})
    store.upsert_interaction(_interaction("a" * 64, 1))
    validation = _interaction("b" * 64, 2)
    validation["updated_at"] = "2026-02-01T00:00:00Z"
    store.upsert_interaction(validation)
    test = _interaction("c" * 64, 3)
    test["updated_at"] = "2026-05-01T00:00:00Z"
    store.upsert_interaction(test)

    plan = plan_cold_eval_backfill(store, train_end)
    assert plan["cold_validation"] == 1
    assert plan["cold_test"] == 1
    assert plan["content_cold_validation"] == 0
    assert plan["content_cold_test"] == 0
    assert plan["tasks"] == [2, 3]


def test_value_backfill_ranks_eval_then_regular_train_support(store):
    cfg = DatasetConfig(splits={"train_end_date": "2025-12-31"})
    # Weak train candidate.
    store.upsert_interaction(_interaction("a" * 64, 1))
    # Two regular train signals should outrank weak-only train metadata.
    for anonymous_id in ("b" * 64, "c" * 64):
        row = _interaction(anonymous_id, 2)
        row["collection_type"] = weights.COLLECTION_TYPE_ID["collect"]
        row["collection_type_name"] = "collect"
        store.upsert_interaction(row)
    # Evaluation evidence is first even with only one interaction.
    row = _interaction("d" * 64, 3)
    row["updated_at"] = "2026-02-01T00:00:00Z"
    store.upsert_interaction(row)

    plan = plan_value_backfill(store, cfg)
    assert plan["tasks"] == [3, 2, 1]
    assert plan["evaluation_candidates"] == 1
    assert plan["regular_train_candidates"] == 1
    assert plan["weak_or_unassigned_only"] == 1
