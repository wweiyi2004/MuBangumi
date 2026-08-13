"""Bangumi response model validation against local fixtures (no network)."""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from src import bangumi


def test_subject_detail_parses(load_fixture):
    detail = bangumi.SubjectDetail.model_validate(load_fixture("subject_detail.json"))
    assert detail.id == 456080
    assert detail.name_cn == "转学后班上的清纯可爱美少女，竟是小时候玩在一起的哥们儿"
    assert detail.date == "2026-07-06"
    assert detail.platform == "TV"
    assert detail.total_episodes == 12
    assert detail.rating.score == 5.1
    assert detail.rating.rank == 9596
    assert detail.rating.total == 428
    assert detail.collection.wish == 647
    assert detail.collection.doing == 1817
    assert len(detail.infobox) == 10
    assert detail.nsfw is False


def test_subject_detail_missing_fields_default(load_fixture):
    """New/unrated subjects come back with null rating/collection etc."""
    detail = bangumi.SubjectDetail.model_validate(load_fixture("subject_detail_missing.json"))
    assert detail.id == 999999
    assert detail.name == "新番未上榜"
    assert detail.name_cn is None
    assert detail.date is None
    assert detail.rating is None
    assert detail.collection is None
    assert detail.infobox is None
    assert detail.tags is None
    assert detail.nsfw is False
    assert detail.images is None


def test_search_page_parses(load_fixture):
    page = bangumi.SearchPage.model_validate(load_fixture("search_page.json"))
    assert page.total == 270
    assert [item.id for item in page.data] == [456080, 777777]
    assert page.data[1].date == "2026-07-01"
    # The search model deliberately keeps ids only; rating is not required.
    assert getattr(page.data[1], "rating", None) is None


def test_calendar_parses(load_fixture):
    days = [bangumi.CalendarDay.model_validate(d) for d in load_fixture("calendar.json")]
    assert len(days) == 2
    assert [i.id for i in days[0].items] == [456080, 888888]
    assert days[1].items == []


def test_collection_page_drops_personal_fields(load_fixture):
    """comment/tags/private/ep_status must NOT survive into the model."""
    page = bangumi.CollectionPage.model_validate(load_fixture("collection_page.json"))
    assert page.total == 3
    first = page.data[0]
    assert first.subject_id == 456080
    assert first.rate == 7
    assert first.type == 1
    assert first.updated_at == "2025-11-25T01:25:16+08:00"
    for name in ("comment", "tags", "private", "ep_status", "vol_status"):
        assert getattr(first, name, None) is None, f"{name} leaked into the model"
    assert page.data[2].updated_at is None
    assert page.data[2].rate == 2


def test_collection_page_can_request_all_collection_types():
    class Client:
        def __init__(self):
            self.path = ""
            self.params = {}

        def get_json(self, path, params=None):
            self.path = path
            self.params = params or {}
            return {"total": 0, "limit": 100, "offset": 0, "data": []}

    client = Client()
    bangumi.fetch_user_collections_page(client, "name/with slash", None, 0, 100)
    assert client.path == "/v0/users/name%2Fwith%20slash/collections"
    assert client.params == {"subject_type": 2, "limit": 100, "offset": 0}


def test_characters_parses(load_fixture):
    chars = [bangumi.CharacterEntry.model_validate(c) for c in load_fixture("characters.json")]
    assert chars[0].name == "示例角色A"
    assert [a.name for a in chars[0].actors] == ["土岐隼一", "田中苑希"]
    assert chars[1].actors[0].name == "土岐隼一"


def test_related_parses(load_fixture):
    related = [bangumi.RelatedEntry.model_validate(r) for r in load_fixture("related.json")]
    assert {r.relation for r in related} == {"书籍", "片头曲", "续作", "前传"}


def test_page_total_missing_is_none_not_zero():
    """The official OpenAPI spec does not require 'total'; an omitted total
    must not masquerade as an already-ended stream (total=0)."""
    page = bangumi.CollectionPage.model_validate({"limit": 100, "offset": 0, "data": []})
    assert page.total is None
    search = bangumi.SearchPage.model_validate({"limit": 25, "offset": 0, "data": []})
    assert search.total is None


def test_invalid_payload_raises_validation_error():
    with pytest.raises(ValidationError):
        bangumi.SearchPage.model_validate({"total": 1, "data": [{"id": "not-an-int"}]})
    with pytest.raises(ValidationError):
        bangumi.CollectionPage.model_validate({"total": "oops", "data": []})
