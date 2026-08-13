"""Public community topic author discovery for local seed-user collection."""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Protocol

from src.http_client import HttpError

TOPIC_LIST_PATH = "/p1/groups/-/topics"
TOPIC_DETAIL_PATH = "/p1/groups/-/topics/{topic_id}"


class JsonClient(Protocol):
    def get_json(self, path: str, params: dict | None = None): ...


@dataclass
class DiscoveryState:
    next_offset: int = 0
    seen_topic_ids: set[int] = field(default_factory=set)

    @classmethod
    def load(cls, path: Path) -> "DiscoveryState":
        if not path.exists():
            return cls()
        raw = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(raw, dict):
            raise ValueError("user seed discovery state must be a JSON object")
        next_offset = int(raw.get("next_offset", 0))
        topic_ids = raw.get("seen_topic_ids", [])
        if next_offset < 0 or not isinstance(topic_ids, list):
            raise ValueError("invalid user seed discovery state")
        return cls(
            next_offset=next_offset,
            seen_topic_ids={int(topic_id) for topic_id in topic_ids},
        )

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_text(
            json.dumps(
                {
                    "next_offset": self.next_offset,
                    "seen_topic_ids": sorted(self.seen_topic_ids),
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        temporary.replace(path)


@dataclass
class DiscoveryResult:
    initial_users: int
    users: set[str]
    list_pages: int = 0
    topic_details: int = 0
    unavailable_topics: int = 0
    exhausted: bool = False

    @property
    def new_users(self) -> int:
        return len(self.users) - self.initial_users


def read_usernames(path: Path) -> set[str]:
    if not path.exists():
        return set()
    usernames: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        username = normalize_username(line)
        if username and not username.startswith("#"):
            usernames.add(username)
    return usernames


def write_usernames(path: Path, usernames: set[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    content = "".join(f"{username}\n" for username in sorted(usernames, key=str.casefold))
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(path)


def normalize_username(value) -> str:
    if not isinstance(value, str):
        return ""
    username = value.strip()
    if not username or len(username) > 255:
        return ""
    if any(character in username for character in ("\x00", "\r", "\n")):
        return ""
    return username


def extract_usernames(payload) -> set[str]:
    usernames: set[str] = set()

    def visit(node) -> None:
        if not isinstance(node, dict):
            return
        creator = node.get("creator")
        if isinstance(creator, dict):
            username = normalize_username(creator.get("username"))
            if username:
                usernames.add(username)
        replies = node.get("replies")
        if isinstance(replies, list):
            for reply in replies:
                visit(reply)

    visit(payload)
    return usernames


def parse_topic_page(payload) -> tuple[list[dict], int]:
    if not isinstance(payload, dict):
        raise ValueError("topic page must be a JSON object")
    data = payload.get("data")
    if not isinstance(data, list):
        raise ValueError("topic page data must be a list")
    topics = [item for item in data if isinstance(item, dict)]
    total = int(payload.get("total", len(topics)))
    return topics, max(total, 0)


def topic_id_of(topic: dict) -> int | None:
    try:
        topic_id = int(topic.get("id", 0))
    except (TypeError, ValueError):
        return None
    return topic_id if topic_id > 0 else None


def discover_usernames(
    client: JsonClient,
    existing_users: set[str],
    state: DiscoveryState,
    *,
    target_users: int,
    max_topic_pages: int,
    max_topics: int,
    page_size: int,
    checkpoint: Callable[[set[str], DiscoveryState], None] | None = None,
) -> DiscoveryResult:
    users = existing_users
    result = DiscoveryResult(initial_users=len(users), users=users)
    if len(users) >= target_users:
        return result

    offset = state.next_offset
    while result.list_pages < max_topic_pages and result.topic_details < max_topics:
        page = client.get_json(
            TOPIC_LIST_PATH,
            params={"mode": "all", "limit": page_size, "offset": offset},
        )
        topics, total = parse_topic_page(page)
        result.list_pages += 1
        if not topics:
            result.exhausted = True
            break

        for topic in topics:
            users.update(extract_usernames(topic))
            if len(users) >= target_users:
                if checkpoint is not None:
                    checkpoint(users, state)
                break
            topic_id = topic_id_of(topic)
            if topic_id is None or topic_id in state.seen_topic_ids:
                continue
            if result.topic_details >= max_topics:
                if checkpoint is not None:
                    checkpoint(users, state)
                break
            try:
                detail = client.get_json(TOPIC_DETAIL_PATH.format(topic_id=topic_id))
            except HttpError as exc:
                if exc.status != 404:
                    raise
                state.seen_topic_ids.add(topic_id)
                result.unavailable_topics += 1
                if checkpoint is not None:
                    checkpoint(users, state)
                continue
            users.update(extract_usernames(detail))
            state.seen_topic_ids.add(topic_id)
            result.topic_details += 1
            if checkpoint is not None:
                checkpoint(users, state)
            if len(users) >= target_users:
                break

        if len(users) >= target_users or result.topic_details >= max_topics:
            break
        state.next_offset = offset + len(topics)
        offset = state.next_offset
        if checkpoint is not None:
            checkpoint(users, state)
        if offset >= total:
            result.exhausted = True
            break

    return result
