"""Bangumi public API endpoints and response models.

Only public, documented API endpoints are used. Response payloads are validated
with pydantic before anything is written to the database; fields we must not
collect (user comments, tags, privacy flags, images) are simply not declared
and are dropped by the model (extra="ignore" is the pydantic v2 default).
"""
from __future__ import annotations

from typing import Any, Optional
from urllib.parse import quote

from pydantic import BaseModel

from src.http_client import BangumiHttpClient
from src.parse import quarter_date_range

SUBJECT_TYPE_ANIME = 2


class Rating(BaseModel):
    score: Optional[float] = None
    total: Optional[int] = None
    rank: Optional[int] = None
    count: Optional[dict[str, Any]] = None


class CollectionCounts(BaseModel):
    wish: Optional[int] = None
    collect: Optional[int] = None
    doing: Optional[int] = None
    on_hold: Optional[int] = None
    dropped: Optional[int] = None


class SubjectDetail(BaseModel):
    id: int
    name: Optional[str] = None
    name_cn: Optional[str] = None
    summary: Optional[str] = None
    date: Optional[str] = None
    platform: Optional[str] = None
    type: Optional[int] = None
    total_episodes: Optional[int] = None
    images: Optional[dict[str, Any]] = None
    infobox: Optional[list[Any]] = None
    tags: Optional[list[Any]] = None
    meta_tags: Optional[list[str]] = None
    rating: Optional[Rating] = None
    collection: Optional[CollectionCounts] = None
    nsfw: Optional[bool] = False


class SearchItem(BaseModel):
    """Lightweight subject summary (calendar / search results) - ids only."""

    id: int
    name: Optional[str] = None
    name_cn: Optional[str] = None
    date: Optional[str] = None
    air_date: Optional[str] = None
    type: Optional[int] = None


class SearchPage(BaseModel):
    # Absent 'total' stays None (the official OpenAPI spec does not require it)
    # so pagination never mistakes a missing total for an already-ended stream.
    total: Optional[int] = None
    limit: int = 25
    offset: int = 0
    data: list[SearchItem] = []


class CalendarDay(BaseModel):
    weekday: dict[str, Any] = {}
    items: list[SearchItem] = []


class ActorRef(BaseModel):
    id: Optional[int] = None
    name: Optional[str] = None


class CharacterEntry(BaseModel):
    id: Optional[int] = None
    name: Optional[str] = None
    relation: Optional[str] = None
    actors: list[ActorRef] = []


class RelatedEntry(BaseModel):
    id: Optional[int] = None
    name: Optional[str] = None
    relation: Optional[str] = None
    type: Optional[int] = None


class CollectionItem(BaseModel):
    """One user's collection entry.

    Deliberately does NOT declare `comment`, `tags`, `private`, `ep_status`,
    `vol_status` or the embedded `subject` object - personal data we must not
    persist. Only the fields needed for implicit feedback are kept.
    """

    subject_id: Optional[int] = None
    subject_type: Optional[int] = None
    rate: Optional[int] = None
    type: Optional[int] = None
    updated_at: Optional[str] = None


class CollectionPage(BaseModel):
    # Absent 'total' stays None (the official OpenAPI spec does not require it)
    # so pagination never mistakes a missing total for an already-ended stream.
    total: Optional[int] = None
    limit: int = 100
    offset: int = 0
    data: list[CollectionItem] = []


def fetch_calendar(client: BangumiHttpClient) -> list[CalendarDay]:
    """Daily broadcast calendar. Served on the legacy root, not under /v0."""
    data = client.get_json("/calendar")
    if not isinstance(data, list):
        raise ValueError("calendar: expected a JSON list at the top level")
    return [CalendarDay.model_validate(day) for day in data]


def search_page(
    client: BangumiHttpClient, year: int, quarter: int, offset: int, limit: int = 25
) -> SearchPage:
    """Paginated anime search within one broadcast quarter (empty keyword)."""
    start, end = quarter_date_range(year, quarter)
    body = {
        "keyword": "",
        "sort": "rank",
        "filter": {
            "type": [SUBJECT_TYPE_ANIME],
            "nsfw": False,
            "air_date": [f">={start}", f"<={end}"],
        },
        "limit": limit,
        "offset": offset,
    }
    return SearchPage.model_validate(client.post_json("/v0/search/subjects", body))


def fetch_subject(client: BangumiHttpClient, subject_id: int) -> SubjectDetail:
    return SubjectDetail.model_validate(
        client.get_json(f"/v0/subjects/{subject_id}")
    )


def fetch_characters(client: BangumiHttpClient, subject_id: int) -> list[CharacterEntry]:
    data = client.get_json(f"/v0/subjects/{subject_id}/characters")
    if not isinstance(data, list):
        raise ValueError("characters: expected a JSON list")
    return [CharacterEntry.model_validate(entry) for entry in data]


def fetch_related(client: BangumiHttpClient, subject_id: int) -> list[RelatedEntry]:
    data = client.get_json(f"/v0/subjects/{subject_id}/subjects")
    if not isinstance(data, list):
        raise ValueError("related subjects: expected a JSON list")
    return [RelatedEntry.model_validate(entry) for entry in data]


def fetch_persons(client: BangumiHttpClient, subject_id: int) -> list[dict[str, Any]]:
    """Staff list; only (id, name, relation) credits are kept."""
    data = client.get_json(f"/v0/subjects/{subject_id}/persons")
    if not isinstance(data, list):
        raise ValueError("persons: expected a JSON list")
    result: list[dict[str, Any]] = []
    for entry in data:
        if isinstance(entry, dict):
            result.append(
                {
                    "id": entry.get("id"),
                    "name": entry.get("name"),
                    "relation": entry.get("relation"),
                }
            )
    return result


def fetch_user_collections_page(
    client: BangumiHttpClient,
    username: str,
    collection_type: Optional[int],
    offset: int,
    limit: int = 100,
) -> CollectionPage:
    """One page of a user's public anime collections (subject_type=2)."""
    params = {
        "subject_type": SUBJECT_TYPE_ANIME,
        "limit": limit,
        "offset": offset,
    }
    if collection_type is not None:
        params["type"] = collection_type
    path = f"/v0/users/{quote(username, safe='')}/collections"
    return CollectionPage.model_validate(client.get_json(path, params=params))
