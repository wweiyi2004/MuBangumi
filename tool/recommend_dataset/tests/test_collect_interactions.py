from __future__ import annotations

from types import SimpleNamespace

from collect_interactions import prioritize_seed_users, work_user
from src import anon_id


class Store:
    def __init__(self):
        self.rows = {}
        self.checkpoints = {}
        self.records = {}

    def seed_user_record(self, username):
        return self.records.get(username)

    def get_checkpoint(self, key):
        return self.checkpoints.get(key)

    def set_checkpoint(self, key, value):
        self.checkpoints[key] = value

    def clear_checkpoints(self, prefix):
        keys = [key for key in self.checkpoints if key.startswith(prefix)]
        for key in keys:
            del self.checkpoints[key]
        return len(keys)

    def upsert_interaction(self, row):
        self.rows[(row["anon_user_id"], row["subject_id"])] = row

    def user_interaction_count(self, anonymous_user_id):
        return sum(key[0] == anonymous_user_id for key in self.rows)

    def prune_user_interactions(self, anonymous_user_id, current_snapshot_marker):
        stale = [
            key
            for key, row in self.rows.items()
            if key[0] == anonymous_user_id
            and row["fetched_at"] != current_snapshot_marker
        ]
        for key in stale:
            del self.rows[key]
        return len(stale)

    def set_seed_user(self, username, anon_user_id, status, items, **kwargs):
        self.records[username] = {
            "status": status,
            "items_fetched": items,
            "pages_fetched": kwargs.get("pages_fetched", 0),
            "next_offset": kwargs.get("next_offset", 0),
            "total_reported": kwargs.get("total_reported"),
            "is_complete": kwargs.get("is_complete", False),
            "stop_reason": kwargs.get("stop_reason"),
        }


class Client:
    def __init__(self, total=2):
        self.total = total

    def get_json(self, path, params=None):
        params = params or {}
        offset = int(params.get("offset", 0))
        limit = int(params.get("limit", 100))
        end = min(offset + limit, self.total)
        return {
            "total": self.total,
            "limit": limit,
            "offset": offset,
            "data": [
                {
                    "subject_id": subject_id,
                    "subject_type": 2,
                    "type": 1 if subject_id % 2 else 2,
                    "rate": 8,
                }
                for subject_id in range(offset + 1, end + 1)
            ],
        }


class FailLog:
    def append(self, record):
        raise AssertionError(record)


def _cfg(*, accepted=("wish",), max_pages=0):
    return SimpleNamespace(
        interactions=SimpleNamespace(
            collection_types=list(accepted),
            page_size=100,
            max_pages_per_run=max_pages,
        )
    )


def test_http_404_is_not_duplicated_by_cli_fail_log():
    """A 403/404 on a user collection is logged exactly once by the client's
    on_failure callback; the CLI must not append a second record."""
    from src import http_client

    recorded = []

    class RecordingFailLog:
        def append(self, record):
            recorded.append(record)

    class Client404:
        def get_json(self, path, params=None):
            raise http_client.HttpError(404, "HTTP 404 for /v0/users/***/collections", url=path)

    store = Store()
    _, status, _ = work_user(
        _cfg(), store, Client404(), RecordingFailLog(), "salt", "public-user", False
    )
    assert status == "unavailable"
    assert recorded == []


def test_combined_stream_filters_types_and_records_completion():
    store = Store()
    _, status, error = work_user(
        _cfg(), store, Client(), FailLog(), "salt", "public-user", False
    )
    assert status == "success"
    assert error is None
    assert [row[1] for row in store.rows] == [1]
    assert list(store.checkpoints.values()) == ["2"]
    record = store.records["public-user"]
    assert record["status"] == "complete"
    assert record["is_complete"] is True
    assert record["total_reported"] == 2
    assert record["next_offset"] == 2


def test_page_budget_marks_truncated_and_next_run_resumes_to_completion():
    store = Store()
    cfg = _cfg(accepted=("wish", "collect"), max_pages=2)

    _, first_status, _ = work_user(
        cfg, store, Client(total=250), FailLog(), "salt", "public-user", False
    )
    assert first_status == "truncated"
    first = store.records["public-user"]
    assert first["status"] == "truncated"
    assert first["is_complete"] is False
    assert first["stop_reason"] == "run_page_limit"
    assert first["next_offset"] == 200
    assert first["items_fetched"] == 200

    _, second_status, _ = work_user(
        cfg, store, Client(total=250), FailLog(), "salt", "public-user", False
    )
    assert second_status == "success"
    final = store.records["public-user"]
    assert final["status"] == "complete"
    assert final["is_complete"] is True
    assert final["next_offset"] == 250
    assert final["total_reported"] == 250
    assert final["pages_fetched"] == 3
    assert final["items_fetched"] == 250


def _item(subject_id, type_=1):
    return {"subject_id": subject_id, "subject_type": 2, "type": type_, "rate": 8}


class ClientNoTotal:
    """Client whose pages omit 'total' (the API spec does not require it)."""

    def __init__(self, pages):
        self.pages = list(pages)

    def get_json(self, path, params=None):
        data = self.pages.pop(0) if self.pages else []
        return {"limit": 100, "offset": int((params or {}).get("offset", 0)), "data": data}


def test_missing_total_paginates_until_empty_page():
    """total=0 must not end the stream after the first page; only an empty
    page (or a known total) marks the collection complete."""
    store = Store()
    client = ClientNoTotal([
        [_item(1), _item(2)],
        [_item(3), _item(4)],
        [_item(5)],
    ])
    _, status, error = work_user(
        _cfg(accepted=("wish", "collect"), max_pages=0),
        store, client, FailLog(), "salt", "public-user", False,
    )
    assert status == "success"
    assert error is None
    assert len(store.rows) == 5
    record = store.records["public-user"]
    assert record["is_complete"] is True
    assert record["stop_reason"] == "end_of_stream"
    assert record["total_reported"] is None


def test_exact_page_boundary_is_complete_when_api_total_is_known():
    store = Store()
    _, status, _ = work_user(
        _cfg(accepted=("wish", "collect"), max_pages=2),
        store,
        Client(total=200),
        FailLog(),
        "salt",
        "public-user",
        False,
    )
    assert status == "success"
    assert store.records["public-user"]["is_complete"] is True
    assert store.records["public-user"]["next_offset"] == 200


def test_refetch_prunes_interactions_missing_from_completed_snapshot():
    store = Store()
    anonymous_id = anon_id.anonymous_user_id("public-user", "salt")
    store.rows[(anonymous_id, 999)] = {
        "anon_user_id": anonymous_id,
        "subject_id": 999,
        "fetched_at": "old-snapshot",
    }

    _, status, _ = work_user(
        _cfg(), store, Client(total=1), FailLog(), "salt", "public-user", True
    )

    assert status == "success"
    assert {key[1] for key in store.rows} == {1}
    assert not any(key.endswith(":refetch_marker") for key in store.checkpoints)


def test_priority_prefers_largest_resumable_checkpoint():
    store = Store()
    salt = "test-salt"
    users = ["new", "small", "large", "done"]
    for name, items, complete in (
        ("small", 100, False),
        ("large", 200, False),
        ("done", 300, True),
    ):
        store.records[name] = {
            "status": "complete" if complete else "ok",
            "items_fetched": items,
            "is_complete": complete,
        }
        anonymous_id = anon_id.anonymous_user_id(name, salt)
        store.checkpoints[f"collections:{anonymous_id}:all"] = str(items)

    ordered = prioritize_seed_users(store, salt, users)
    assert ordered[:2] == ["large", "small"]
    assert ordered[-1] == "done"


def test_priority_maximizes_completions_when_totals_are_known():
    store = Store()
    salt = "test-salt"
    for name, offset, total in (
        ("outlier", 400, 10000),
        ("nearly-done", 200, 220),
        ("medium", 200, 600),
    ):
        store.records[name] = {
            "status": "truncated",
            "items_fetched": offset,
            "is_complete": False,
            "total_reported": total,
        }
        anonymous_id = anon_id.anonymous_user_id(name, salt)
        store.checkpoints[f"collections:{anonymous_id}:all"] = str(offset)
    ordered = prioritize_seed_users(
        store, salt, ["outlier", "medium", "nearly-done"]
    )
    assert ordered == ["nearly-done", "medium", "outlier"]


def test_priority_can_put_uncollected_seed_users_first():
    store = Store()
    salt = "test-salt"
    store.records["partial"] = {
        "status": "truncated",
        "items_fetched": 200,
        "is_complete": False,
        "total_reported": 300,
    }
    anonymous_id = anon_id.anonymous_user_id("partial", salt)
    store.checkpoints[f"collections:{anonymous_id}:all"] = "200"
    ordered = prioritize_seed_users(
        store,
        salt,
        ["partial", "new"],
        new_users_first=True,
    )
    assert ordered == ["new", "partial"]
