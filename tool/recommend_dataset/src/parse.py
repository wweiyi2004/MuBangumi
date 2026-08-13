"""Parsing helpers: dates, seasons, infobox, tags.

All functions here are pure and defensive: missing or malformed input yields
None/empty rather than raising, so a single bad record never kills the run.
"""
from __future__ import annotations

import datetime as dt
from typing import Any, Optional

SEASON_NAMES = {1: "winter", 2: "spring", 3: "summer", 4: "autumn"}


def parse_date_parts(raw: Optional[str]) -> tuple[Optional[int], Optional[int], Optional[int]]:
    """Parse 'YYYY', 'YYYY-MM' or 'YYYY-MM-DD' -> (year, month, day).

    Returns (None, None, None) for empty or unparseable input.
    """
    if not raw:
        return (None, None, None)
    text = str(raw).strip()
    parts = text.split("-")
    nums: list[int] = []
    for part in parts:
        if part.isdigit():
            nums.append(int(part))
        else:
            return (None, None, None)
    if not nums or not (1900 <= nums[0] <= 2100):
        return (None, None, None)
    year = nums[0]
    # An invalid month/day makes the whole date unusable - never approximate
    # it (a guessed 01-01 could leak an item into the wrong temporal split).
    if len(nums) >= 2 and not (1 <= nums[1] <= 12):
        return (None, None, None)
    if len(nums) >= 3 and not (1 <= nums[2] <= 31):
        return (None, None, None)
    month = nums[1] if len(nums) >= 2 else None
    day = nums[2] if len(nums) >= 3 else None
    return (year, month, day)


def parse_date_flexible(raw: Optional[str]) -> Optional[dt.date]:
    """Parse 'YYYY[-MM[-DD]]' into a date (month/day default to 1)."""
    year, month, day = parse_date_parts(raw)
    if year is None:
        return None
    try:
        return dt.date(year, month or 1, day or 1)
    except ValueError:
        # Impossible calendar dates (e.g. 2026-04-31) pass parse_date_parts'
        # range checks but fail construction - treat them as missing.
        return None


def season_of_month(month: Optional[int]) -> Optional[int]:
    if not month:
        return None
    return (month - 1) // 3 + 1


def season_name(month: Optional[int]) -> str:
    return SEASON_NAMES.get(season_of_month(month) or 0, "")


def quarter_key(year: Optional[int], month: Optional[int]) -> Optional[str]:
    season = season_of_month(month)
    if year is None or season is None:
        return None
    return f"{year}Q{season}"


def quarter_date_range(year: int, quarter: int) -> tuple[str, str]:
    """Inclusive [start, end] dates of a broadcast quarter, as ISO strings."""
    start_month = (quarter - 1) * 3 + 1
    start = dt.date(year, start_month, 1)
    if quarter >= 4:
        end = dt.date(year + 1, 1, 1) - dt.timedelta(days=1)
    else:
        end = dt.date(year, start_month + 3, 1) - dt.timedelta(days=1)
    return start.isoformat(), end.isoformat()


def dedupe(values: list[str]) -> list[str]:
    """Deduplicate preserving first-seen order."""
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        item = value.strip()
        if item and item not in seen:
            seen.add(item)
            result.append(item)
    return result


def parse_infobox(infobox: Optional[list[Any]]) -> dict[str, list[str]]:
    """Flatten the API infobox list into {key: [values]}.

    Handles both plain string values and grouped values ([{"v": ...}]).
    """
    result: dict[str, list[str]] = {}
    for entry in infobox or []:
        if not isinstance(entry, dict):
            continue
        raw_key = entry.get("key")
        if not isinstance(raw_key, str):
            continue
        key = raw_key.strip()
        if not key:
            continue
        value = entry.get("value")
        values: list[str] = []
        if isinstance(value, str):
            values = [value]
        elif isinstance(value, list):
            for item in value:
                if isinstance(item, str):
                    values.append(item)
                elif isinstance(item, dict) and item.get("v") is not None:
                    values.append(str(item["v"]))
        if values:
            result.setdefault(key, []).extend(dedupe(values))
    return result


def extract_cold_start_features(
    info: dict[str, list[str]],
) -> dict[str, list[str]]:
    """Stable infobox keys used for content cold start.

    Keys are matched by prefix so small naming variations on the wiki
    (e.g. "导演" vs "导演·分镜") still match; empty fields are omitted.
    """
    wanted = {
        "production": ("动画制作", "制作"),
        "director": ("导演",),
        "series_composer": ("系列构成",),
        "original_work": ("原作",),
        "music": ("音乐",),
    }
    result: dict[str, list[str]] = {}
    for out_key, prefixes in wanted.items():
        values: list[str] = []
        for key, key_values in info.items():
            if any(key.startswith(prefix) for prefix in prefixes):
                values.extend(key_values)
        if values:
            result[out_key] = dedupe(values)
    return result


def clean_meta_tags(meta_tags: Optional[list[str]]) -> list[str]:
    return dedupe([str(tag) for tag in (meta_tags or []) if tag])


def tag_names(tags: Optional[list[Any]]) -> list[str]:
    result: list[str] = []
    for tag in tags or []:
        if isinstance(tag, dict) and tag.get("name"):
            result.append(str(tag["name"]))
    return dedupe(result)


def image_url_of(images: Optional[dict[str, Any]]) -> Optional[str]:
    """Pick the largest cover variant if present; None otherwise."""
    if not isinstance(images, dict):
        return None
    for key in ("large", "common", "medium", "small", "grid"):
        value = images.get(key)
        if isinstance(value, str) and value:
            return value
    return None


def voice_actor_names(characters: list[Any]) -> list[str]:
    """Actor (声优) names from the characters endpoint, deduplicated."""
    names: list[str] = []
    for character in characters:
        for actor in getattr(character, "actors", []) or []:
            if actor.name:
                names.append(actor.name)
    return dedupe(names)


def related_entries(related: list[Any]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for entry in related:
        result.append(
            {
                "id": entry.id,
                "name": entry.name,
                "relation": entry.relation,
                "type": entry.type,
            }
        )
    return result


def is_prequel_sequel(relation: Optional[str]) -> bool:
    if not relation:
        return False
    return any(token in relation for token in ("前传", "续作", "前作", "后作", "前日谈", "后日谈"))
