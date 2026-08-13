"""Temporal splits and item class flags.

Two complementary split concepts live here:

1. Air-date item windows (legacy, kept for compatibility):
   train / validation / test by first air date - used for new_release flags.

2. Interaction splits (strict, audit-friendly; used for training/eval files):
   driven by interaction.updated_at converted to UTC:
     - updated_at <= train_end            -> train
     - updated_at in the next quarter     -> validation
     - updated_at in the quarter after    -> test
     - missing / unparseable / naive      -> unassigned
     - later than the test window         -> future (never in any file)
     - earlier than the item air date     -> invalid_temporal (never in any file)

Item classes:
  warm_item          - >= 1 positive interaction in the train window
  few_shot_item      - 1..20 positive train interactions (subset of warm)
  train_zero_interaction - aired before train_end but zero positive train interactions
  cold_item          - zero train interactions, but positive val/test interactions
  new_release        - air date falls in the validation or test quarter
  strict_cold_new_release - cold_item AND new_release
  unknown_air_date   - air date missing (never silently treated as a train item)
"""
from __future__ import annotations

import datetime as dt
from typing import Optional

from src.parse import parse_date_flexible

SPLIT_TRAIN = "train"
SPLIT_VALIDATION = "validation"
SPLIT_TEST = "test"
SPLIT_UNASSIGNED = "unassigned"
SPLIT_FUTURE = "future"
SPLIT_INVALID_TEMPORAL = "invalid_temporal"

# Reason strings for interaction_split()
REASON_OK = "ok"
REASON_MISSING_UPDATED_AT = "missing_updated_at"
REASON_NAIVE_DATETIME = "naive_datetime"
REASON_PARSE_ERROR = "parse_error"
REASON_AFTER_TEST_WINDOW = "after_test_window"
REASON_BEFORE_AIR_DATE = "before_air_date"


def quarter_key_of(day: dt.date) -> str:
    return f"{day.year}Q{(day.month - 1) // 3 + 1}"


def next_quarter(key: str) -> str:
    year, _, quarter = key.partition("Q")
    qn = int(quarter)
    if qn == 4:
        return f"{int(year) + 1}Q1"
    return f"{year}Q{qn + 1}"


def quarter_start(key: str) -> dt.date:
    year, _, quarter = key.partition("Q")
    qn = int(quarter)
    return dt.date(int(year), (qn - 1) * 3 + 1, 1)


def quarter_end(key: str) -> dt.date:
    """Inclusive last day of the quarter (handles 30/31-day months)."""
    start = quarter_start(key)
    if start.month == 10:
        return dt.date(start.year, 12, 31)
    next_start = dt.date(start.year, start.month + 3, 1)
    return next_start - dt.timedelta(days=1)


def split_for_date(air_date_text: Optional[str], train_end: dt.date) -> Optional[str]:
    """Assign a subject to train/validation/test by its air date.

    Returns None for missing dates or dates beyond the test quarter end.
    """
    day = parse_date_flexible(air_date_text)
    if day is None:
        return None
    if day <= train_end:
        return SPLIT_TRAIN
    validation_key = next_quarter(quarter_key_of(train_end))
    if day <= quarter_end(validation_key):
        return SPLIT_VALIDATION
    test_key = next_quarter(validation_key)
    if day <= quarter_end(test_key):
        return SPLIT_TEST
    return None


def parse_iso_datetime(text: Optional[str]) -> Optional[dt.datetime]:
    """ISO-8601 timestamp ('Z' or numeric offset) -> aware UTC datetime.

    Naive datetimes are rejected (None): comparing naive and aware datetimes is
    a source of silent temporal leakage, so mixed usage is not allowed.
    """
    if not text:
        return None
    try:
        parsed = dt.datetime.fromisoformat(str(text).strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(dt.timezone.utc)


def split_windows(train_end_date: dt.date) -> dict[str, dt.datetime]:
    """UTC time windows derived from the configured train end date.

    train_end      : final microsecond of train_end_date UTC (inclusive)
    validation     : the following natural quarter
    test           : the quarter after validation
    """
    train_end = dt.datetime.combine(
        train_end_date, dt.time.max, tzinfo=dt.timezone.utc
    )
    validation_key = next_quarter(quarter_key_of(train_end_date))
    test_key = next_quarter(validation_key)
    val_start = dt.datetime.combine(
        quarter_start(validation_key), dt.time(0, 0), tzinfo=dt.timezone.utc
    )
    val_end = dt.datetime.combine(
        quarter_end(validation_key), dt.time.max, tzinfo=dt.timezone.utc
    )
    test_start = dt.datetime.combine(
        quarter_start(test_key), dt.time(0, 0), tzinfo=dt.timezone.utc
    )
    test_end = dt.datetime.combine(
        quarter_end(test_key), dt.time.max, tzinfo=dt.timezone.utc
    )
    return {
        "train_end": train_end,
        "validation_start": val_start,
        "validation_end": val_end,
        "test_start": test_start,
        "test_end": test_end,
        "validation_key": validation_key,
        "test_key": test_key,
    }


def interaction_split(
    updated_at_text: Optional[str],
    air_date_text: Optional[str],
    train_end_date: dt.date,
) -> tuple[str, str]:
    """Assign an interaction to a temporal split by its updated_at (UTC).

    Returns (split, reason); split is one of
    train/validation/test/unassigned/future/invalid_temporal.
    """
    parsed = parse_iso_datetime(updated_at_text)
    if not updated_at_text:
        return SPLIT_UNASSIGNED, REASON_MISSING_UPDATED_AT
    if parsed is None:
        # Distinguish "timestamp without an offset" from garbage: if
        # fromisoformat can parse it at all, the text is a naive datetime.
        try:
            dt.datetime.fromisoformat(str(updated_at_text).strip().replace("Z", "+00:00"))
        except ValueError:
            return SPLIT_UNASSIGNED, REASON_PARSE_ERROR
        return SPLIT_UNASSIGNED, REASON_NAIVE_DATETIME

    windows = split_windows(train_end_date)
    air_day = parse_date_flexible(air_date_text)
    if air_day is not None and parsed.date() < air_day:
        return SPLIT_INVALID_TEMPORAL, REASON_BEFORE_AIR_DATE

    if parsed <= windows["train_end"]:
        return SPLIT_TRAIN, REASON_OK
    if parsed <= windows["validation_end"]:
        return SPLIT_VALIDATION, REASON_OK
    if parsed <= windows["test_end"]:
        return SPLIT_TEST, REASON_OK
    return SPLIT_FUTURE, REASON_AFTER_TEST_WINDOW


def compute_item_classes(
    split_map: dict[int, Optional[str]],
    train_counts: dict[int, int],
    val_test_interacted: set[int],
) -> dict[int, list[str]]:
    """Legacy air-date-split item flags (kept for compatibility)."""
    per_item: dict[int, list[str]] = {}
    for sid, split in split_map.items():
        flags: list[str] = []
        if split == SPLIT_TRAIN:
            count = train_counts.get(sid, 0)
            if count > 0:
                flags.append("warm_item")
                if count <= 20:
                    flags.append("few_shot_item")
            else:
                flags.append("train_zero_interaction")
        elif split in (SPLIT_VALIDATION, SPLIT_TEST):
            if sid in val_test_interacted:
                flags.append("cold_item")
            flags.append("new_release")
        if flags:
            per_item[sid] = flags
    return per_item


def compute_item_flags(
    air_dates: dict[int, Optional[str]],
    train_positive_counts: dict[int, int],
    val_test_positive_ids: set[int],
    train_end_date: dt.date,
) -> dict[int, list[str]]:
    """Strict item flags driven by interaction windows + air dates.

    air_dates              : subject_id -> raw air date string (may be None)
    train_positive_counts  : subject_id -> positive interactions in the train window
    val_test_positive_ids  : subjects with positive interactions in val/test windows

    cold_item requires BOTH zero train interactions AND presence in val/test -
    an item is never "cold" just because it airs in the validation quarter.
    """
    windows = split_windows(train_end_date)
    per_item: dict[int, list[str]] = {}
    for sid, raw in air_dates.items():
        flags: list[str] = []
        train_count = train_positive_counts.get(sid, 0)
        air_day = parse_date_flexible(raw)

        if air_day is None:
            flags.append("unknown_air_date")
        else:
            item_split = split_for_date(raw, train_end_date)
            if item_split in (SPLIT_VALIDATION, SPLIT_TEST):
                flags.append("new_release")
            if air_day <= train_end_date and train_count == 0:
                flags.append("train_zero_interaction")

        if train_count > 0:
            flags.append("warm_item")
            if train_count <= 20:
                flags.append("few_shot_item")
        if train_count == 0 and sid in val_test_positive_ids:
            flags.append("cold_item")
        if "cold_item" in flags and "new_release" in flags:
            flags.append("strict_cold_new_release")
        if flags:
            per_item[sid] = flags
    return per_item
