"""Strict temporal splits: timezone parsing, boundaries, leakage, item flags."""
from __future__ import annotations

import datetime as dt

import pytest

from src import splits

TRAIN_END = dt.date(2025, 12, 31)


# ------------------------------------------------------------- parsing
def test_parse_iso_datetime_z():
    parsed = splits.parse_iso_datetime("2025-12-31T23:59:59Z")
    assert parsed == dt.datetime(2025, 12, 31, 23, 59, 59, tzinfo=dt.timezone.utc)


def test_parse_iso_datetime_plus0800():
    parsed = splits.parse_iso_datetime("2026-01-01T00:00:00+08:00")
    assert parsed == dt.datetime(2025, 12, 31, 16, 0, 0, tzinfo=dt.timezone.utc)


def test_parse_iso_datetime_negative_offset():
    parsed = splits.parse_iso_datetime("2026-03-31T18:00:00-06:00")
    assert parsed == dt.datetime(2026, 4, 1, 0, 0, 0, tzinfo=dt.timezone.utc)


def test_naive_datetime_rejected():
    assert splits.parse_iso_datetime("2025-12-31T23:59:59") is None
    assert splits.parse_iso_datetime("2025-12-31 23:59:59") is None


def test_parse_iso_datetime_garbage():
    assert splits.parse_iso_datetime("not a date") is None
    assert splits.parse_iso_datetime(None) is None
    assert splits.parse_iso_datetime("") is None


# ------------------------------------------------------------- boundaries
def test_train_boundary_inclusive():
    assert splits.interaction_split("2025-12-31T23:59:59Z", None, TRAIN_END) == ("train", "ok")
    assert splits.interaction_split("2025-12-31T23:59:59.999999Z", None, TRAIN_END)[0] == "train"
    assert splits.interaction_split("2026-01-01T00:00:00Z", None, TRAIN_END)[0] == "validation"


def test_plus0800_crosses_into_train():
    """2026-01-01 00:00 +08:00 is still 2025-12-31 16:00 UTC -> train."""
    assert splits.interaction_split("2026-01-01T00:00:00+08:00", None, TRAIN_END)[0] == "train"


def test_validation_quarter_boundaries():
    assert splits.interaction_split("2026-01-01T00:00:00Z", None, TRAIN_END)[0] == "validation"
    assert splits.interaction_split("2026-03-31T23:59:59Z", None, TRAIN_END)[0] == "validation"
    assert splits.interaction_split("2026-03-31T23:59:59.999999Z", None, TRAIN_END)[0] == "validation"
    assert splits.interaction_split("2026-04-01T00:00:00Z", None, TRAIN_END)[0] == "test"


def test_test_quarter_boundaries():
    assert splits.interaction_split("2026-04-01T00:00:00Z", None, TRAIN_END)[0] == "test"
    assert splits.interaction_split("2026-06-30T23:59:59Z", None, TRAIN_END)[0] == "test"
    assert splits.interaction_split("2026-06-30T23:59:59.999999Z", None, TRAIN_END)[0] == "test"
    assert splits.interaction_split("2026-07-01T00:00:00Z", None, TRAIN_END)[0] == "future"


def test_window_derivation():
    windows = splits.split_windows(TRAIN_END)
    assert windows["train_end"] == dt.datetime(2025, 12, 31, 23, 59, 59, 999999, tzinfo=dt.timezone.utc)
    assert windows["validation_key"] == "2026Q1"
    assert windows["test_key"] == "2026Q2"
    assert windows["validation_end"] == dt.datetime(2026, 3, 31, 23, 59, 59, 999999,
                                                    tzinfo=dt.timezone.utc)
    assert windows["test_end"] == dt.datetime(2026, 6, 30, 23, 59, 59, 999999,
                                              tzinfo=dt.timezone.utc)


def test_window_derivation_rollover():
    windows = splits.split_windows(dt.date(2024, 12, 31))
    assert windows["validation_key"] == "2025Q1"
    assert windows["test_key"] == "2025Q2"


# ------------------------------------------------------------- quality flags
def test_missing_updated_at():
    split, reason = splits.interaction_split(None, None, TRAIN_END)
    assert split == "unassigned" and reason == "missing_updated_at"
    split, reason = splits.interaction_split("", None, TRAIN_END)
    assert split == "unassigned"


def test_naive_updated_at_unassigned():
    split, reason = splits.interaction_split("2025-06-01T10:00:00", None, TRAIN_END)
    assert split == "unassigned" and reason == "naive_datetime"


def test_parse_error_updated_at_unassigned():
    split, reason = splits.interaction_split("明天", None, TRAIN_END)
    assert split == "unassigned" and reason == "parse_error"


def test_invalid_temporal_before_air_date():
    split, reason = splits.interaction_split("2025-06-01T00:00:00Z", "2025-09-01", TRAIN_END)
    assert split == "invalid_temporal" and reason == "before_air_date"


def test_air_date_missing_skips_temporal_check():
    split, _ = splits.interaction_split("2025-06-01T00:00:00Z", None, TRAIN_END)
    assert split == "train"  # no air date -> no invalid_temporal, still bucketed


def test_train_contains_no_post_cutoff_interactions():
    windows = splits.split_windows(TRAIN_END)
    cases = [
        "2025-12-31T23:59:59Z",
        "2025-12-31T10:00:00+08:00",
        "2025-06-01T00:00:00Z",
        "2025-11-30T23:59:59+08:00",
    ]
    for text in cases:
        split, reason = splits.interaction_split(text, None, TRAIN_END)
        assert split == "train", (text, split)
        assert reason == "ok"
        parsed = splits.parse_iso_datetime(text)
        assert parsed <= windows["train_end"]


# ------------------------------------------------------------- item flags
def test_cold_item_requires_real_val_test_interactions():
    air_dates = {1: "2026-01-15", 2: "2026-01-15", 3: "2025-01-01"}
    train_counts = {1: 3, 2: 0, 3: 1}
    val_test_positive = {1, 2}
    flags = splits.compute_item_flags(air_dates, train_counts, val_test_positive, TRAIN_END)

    assert "warm_item" in flags[1]
    assert "new_release" in flags[1]
    assert "cold_item" not in flags[1]      # has train interactions -> not cold
    assert "strict_cold_new_release" not in flags[1]

    assert "cold_item" in flags[2]          # zero train, positive in val/test
    assert "new_release" in flags[2]
    assert "strict_cold_new_release" in flags[2]
    assert "warm_item" not in flags[2]

    assert "warm_item" in flags[3]
    assert "new_release" not in flags[3]    # aired in the train window
    assert "train_zero_interaction" not in flags[3]


def test_airing_in_validation_quarter_alone_is_not_cold():
    """An item that airs in the validation quarter but has no val/test
    interaction is a new_release but NOT a cold_item."""
    air_dates = {1: "2026-02-01"}
    flags = splits.compute_item_flags(air_dates, {}, set(), TRAIN_END)
    assert flags[1] == ["new_release"]
    assert "cold_item" not in flags[1]


def test_train_zero_interaction_flag():
    air_dates = {1: "2025-01-01", 2: "2025-01-01"}
    train_counts = {1: 0, 2: 5}
    flags = splits.compute_item_flags(air_dates, train_counts, set(), TRAIN_END)
    assert "train_zero_interaction" in flags[1]
    assert "train_zero_interaction" not in flags[2]
    assert "warm_item" not in flags[1]


def test_unknown_air_date_flag():
    air_dates = {1: None, 2: "2026-02-01"}
    train_counts = {1: 5}
    flags = splits.compute_item_flags(air_dates, train_counts, {1}, TRAIN_END)
    assert "unknown_air_date" in flags[1]
    assert "warm_item" in flags[1]          # train interaction is still train
    assert "strict_cold_new_release" not in flags[1]  # no air date -> excluded


def test_item_flag_counts_aggregate():
    air_dates = {1: "2025-01-01", 2: "2025-01-01", 3: "2026-02-01",
                 4: "2026-05-01", 5: "2026-02-01", 6: None, 7: "2025-06-01"}
    train_counts = {1: 25, 2: 5, 7: 0}  # 3 and 5 have zero train interactions
    val_test_positive = {3, 5}
    flags = splits.compute_item_flags(air_dates, train_counts, val_test_positive, TRAIN_END)
    flat = [f for values in flags.values() for f in values]
    assert flat.count("warm_item") == 2          # items 1, 2
    assert flat.count("few_shot_item") == 1      # item 2 (1..20 train interactions)
    assert flat.count("cold_item") == 2          # items 3, 5
    assert flat.count("new_release") == 3        # items 3, 4, 5
    assert flat.count("strict_cold_new_release") == 2  # items 3, 5
    assert flat.count("train_zero_interaction") == 1   # item 7
    assert flat.count("unknown_air_date") == 1   # item 6
