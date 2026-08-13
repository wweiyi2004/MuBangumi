"""Parsing helpers: dates, seasons, quarters, infobox, tags, enrichment."""
from __future__ import annotations

import datetime as dt

from src import bangumi, parse


def test_parse_date_full():
    assert parse.parse_date_parts("2026-07-06") == (2026, 7, 6)


def test_parse_date_flexible_impossible_calendar_dates():
    """'2026-04-31' passes parse_date_parts' range checks but is not a real
    date; a bad record must yield None instead of killing the run."""
    assert parse.parse_date_flexible("2026-04-31") is None  # April has 30 days
    assert parse.parse_date_flexible("2026-02-31") is None  # Feb has 28/29 days
    assert parse.parse_date_flexible("2026-02-29") is None  # 2026 is not a leap year
    assert parse.parse_date_flexible("2024-02-29") == dt.date(2024, 2, 29)
    assert parse.parse_date_flexible("2026-07-06") == dt.date(2026, 7, 6)


def test_parse_date_year_month():
    assert parse.parse_date_parts("2026-07") == (2026, 7, None)


def test_parse_date_year_only():
    assert parse.parse_date_parts("2026") == (2026, None, None)


def test_parse_date_empty():
    assert parse.parse_date_parts(None) == (None, None, None)
    assert parse.parse_date_parts("") == (None, None, None)
    assert parse.parse_date_parts("  ") == (None, None, None)


def test_parse_date_invalid():
    assert parse.parse_date_parts("未知时间") == (None, None, None)
    assert parse.parse_date_parts("123") == (None, None, None)  # year < 1900
    assert parse.parse_date_parts("2026-13") == (None, None, None)  # invalid month
    assert parse.parse_date_parts("2026-13-99") == (None, None, None)
    assert parse.parse_date_parts("2026-07-99") == (None, None, None)  # invalid day


def test_season_of_month():
    assert [parse.season_of_month(m) for m in (1, 3, 4, 6, 7, 9, 10, 12)] == [1, 1, 2, 2, 3, 3, 4, 4]
    assert parse.season_of_month(None) is None


def test_season_name():
    assert parse.season_name(1) == "winter"
    assert parse.season_name(7) == "summer"
    assert parse.season_name(10) == "autumn"
    assert parse.season_name(None) == ""


def test_quarter_key():
    assert parse.quarter_key(2026, 7) == "2026Q3"
    assert parse.quarter_key(2026, None) is None
    assert parse.quarter_key(None, 7) is None


def test_quarter_date_range():
    assert parse.quarter_date_range(2026, 1) == ("2026-01-01", "2026-03-31")
    assert parse.quarter_date_range(2026, 2) == ("2026-04-01", "2026-06-30")
    assert parse.quarter_date_range(2026, 3) == ("2026-07-01", "2026-09-30")
    assert parse.quarter_date_range(2026, 4) == ("2026-10-01", "2026-12-31")


def test_infobox_grouped_and_plain_values():
    infobox = [
        {"key": "中文名", "value": "示例"},
        {"key": "别名", "value": [{"v": "A"}, {"v": "A"}, {"v": "B"}]},
        {"key": "话数", "value": "12"},
        {"key": "无值字段", "value": None},
    ]
    parsed = parse.parse_infobox(infobox)
    assert parsed["中文名"] == ["示例"]
    assert parsed["别名"] == ["A", "B"]  # deduplicated, order kept
    assert parsed["话数"] == ["12"]
    assert "无值字段" not in parsed


def test_infobox_malformed_entries():
    assert parse.parse_infobox(None) == {}
    assert parse.parse_infobox([]) == {}
    assert parse.parse_infobox([{"key": 123, "value": "x"}, "junk", {"value": "no key"}]) == {}


def test_cold_start_features_from_fixture(load_fixture):
    detail = load_fixture("subject_detail.json")
    info = parse.parse_infobox(detail["infobox"])
    features = parse.extract_cold_start_features(info)
    assert features["production"] == ["示例动画公司"]
    assert features["director"] == ["示例监督"]
    assert features["series_composer"] == ["示例构成"]
    assert features["original_work"] == ["示例文库轻小说"]
    assert features["music"] == ["示例音乐家"]


def test_cold_start_features_missing():
    assert parse.extract_cold_start_features({}) == {}


def test_meta_tags_dedupe():
    assert parse.clean_meta_tags(["校园", "TV", "TV", "恋爱", "日本", "日本"]) == [
        "校园", "TV", "恋爱", "日本",
    ]
    assert parse.clean_meta_tags(None) == []


def test_tag_names():
    tags = [{"name": "恋爱", "count": 1}, {"name": "恋爱", "count": 2}, "junk"]
    assert parse.tag_names(tags) == ["恋爱"]
    assert parse.tag_names(None) == []


def test_image_url_prefers_large():
    images = {"small": "http://lain.bgm.tv/s.jpg", "large": "http://lain.bgm.tv/l.jpg"}
    assert parse.image_url_of(images) == "http://lain.bgm.tv/l.jpg"
    assert parse.image_url_of(None) is None
    assert parse.image_url_of({}) is None


def test_voice_actor_names_dedupe(load_fixture):
    characters = [bangumi.CharacterEntry.model_validate(c) for c in load_fixture("characters.json")]
    names = parse.voice_actor_names(characters)
    assert names == ["土岐隼一", "田中苑希"]  # shared actor appears once


def test_related_prequel_sequel(load_fixture):
    related = [bangumi.RelatedEntry.model_validate(r) for r in load_fixture("related.json")]
    entries = parse.related_entries(related)
    assert parse.is_prequel_sequel("续作") is True
    assert parse.is_prequel_sequel("前传") is True
    assert parse.is_prequel_sequel("片头曲") is False
    assert parse.is_prequel_sequel(None) is False
    ps = [e for e in entries if parse.is_prequel_sequel(e["relation"])]
    assert {e["id"] for e in ps} == {990001, 990002}
