from __future__ import annotations

import json

from src import user_seeds


def _user(username: str) -> dict:
    return {"username": username, "nickname": f"name-{username}"}


def test_extract_usernames_from_topic_and_nested_replies():
    payload = {
        "creator": _user("op"),
        "replies": [
            {"creator": _user("alice"), "replies": []},
            {
                "creator": _user("bob"),
                "replies": [
                    {"creator": _user("alice")},
                    {"creator": {"username": "  carol  "}},
                ],
            },
        ],
    }
    assert user_seeds.extract_usernames(payload) == {"op", "alice", "bob", "carol"}


def test_state_round_trip(tmp_path):
    path = tmp_path / "state.json"
    state = user_seeds.DiscoveryState(next_offset=100, seen_topic_ids={3, 1, 2})
    state.save(path)
    assert user_seeds.DiscoveryState.load(path) == state
    raw = json.loads(path.read_text(encoding="utf-8"))
    assert raw["seen_topic_ids"] == [1, 2, 3]


def test_user_file_merge_helpers_do_not_emit_comments(tmp_path):
    path = tmp_path / "users.txt"
    path.write_text("# local\nalice\n\nalice\nbob\n", encoding="utf-8")
    assert user_seeds.read_usernames(path) == {"alice", "bob"}
    user_seeds.write_usernames(path, {"bob", "alice"})
    assert path.read_text(encoding="utf-8") == "alice\nbob\n"


class FakeClient:
    def __init__(self):
        self.calls: list[tuple[str, dict | None]] = []

    def get_json(self, path: str, params: dict | None = None):
        self.calls.append((path, params))
        if path == user_seeds.TOPIC_LIST_PATH:
            return {
                "total": 2,
                "data": [
                    {"id": 10, "creator": _user("author-a")},
                    {"id": 20, "creator": _user("author-b")},
                ],
            }
        if path.endswith("/10"):
            return {"replies": [{"creator": _user("reply-a")}]}
        if path.endswith("/20"):
            return {"replies": [{"creator": _user("reply-b")}]}
        raise AssertionError(path)


def test_discovery_stops_at_target_and_checkpoints():
    client = FakeClient()
    state = user_seeds.DiscoveryState()
    checkpoints = []
    result = user_seeds.discover_usernames(
        client,
        {"existing"},
        state,
        target_users=4,
        max_topic_pages=2,
        max_topics=10,
        page_size=50,
        checkpoint=lambda users, current: checkpoints.append(
            (set(users), set(current.seen_topic_ids))
        ),
    )
    assert result.users == {"existing", "author-a", "author-b", "reply-a"}
    assert result.new_users == 3
    assert result.list_pages == 1
    assert result.topic_details == 1
    assert state.seen_topic_ids == {10}
    assert checkpoints[-1][0] == result.users


def test_discovery_skips_seen_topics_and_advances_page():
    client = FakeClient()
    state = user_seeds.DiscoveryState(seen_topic_ids={10})
    result = user_seeds.discover_usernames(
        client,
        set(),
        state,
        target_users=10,
        max_topic_pages=1,
        max_topics=10,
        page_size=50,
    )
    detail_paths = [path for path, _ in client.calls if path != user_seeds.TOPIC_LIST_PATH]
    assert detail_paths == [user_seeds.TOPIC_DETAIL_PATH.format(topic_id=20)]
    assert state.next_offset == 2
    assert result.exhausted is True
