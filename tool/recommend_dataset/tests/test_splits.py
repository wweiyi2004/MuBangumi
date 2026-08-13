"""Temporal splits: quarter math, assignment, no-future-leak, item classes."""
from __future__ import annotations

import datetime as dt

from src import splits


def test_next_quarter_rollover():
    assert splits.next_quarter("2025Q4") == "2026Q1"
    assert splits.next_quarter("2026Q3") == "2026Q4"
    assert splits.next_quarter("2026Q1") == "2026Q2"


def test_quarter_boundaries():
    assert splits.quarter_start("2026Q1") == dt.date(2026, 1, 1)
    assert splits.quarter_end("2026Q1") == dt.date(2026, 3, 31)
    assert splits.quarter_start("2026Q4") == dt.date(2026, 10, 1)
    assert splits.quarter_end("2026Q4") == dt.date(2026, 12, 31)


def test_split_assignment():
    train_end = dt.date(2025, 12, 31)
    assert splits.split_for_date("2025-12-31", train_end) == "train"
    assert splits.split_for_date("2025-01-15", train_end) == "train"
    assert splits.split_for_date("2026-01-01", train_end) == "validation"
    assert splits.split_for_date("2026-03-31", train_end) == "validation"
    assert splits.split_for_date("2026-04-01", train_end) == "test"
    assert splits.split_for_date("2026-06-30", train_end) == "test"
    assert splits.split_for_date("2026-07-01", train_end) is None  # beyond window
    assert splits.split_for_date(None, train_end) is None
    assert splits.split_for_date("", train_end) is None
    assert splits.split_for_date("2026", train_end) == "validation"  # year-only -> Jan 1
    assert splits.split_for_date("2024-05", train_end) == "train"


def test_quarter_boundary_crossing():
    train_end = dt.date(2026, 6, 30)  # validation = 2026Q3, test = 2026Q4
    assert splits.split_for_date("2026-06-30", train_end) == "train"
    assert splits.split_for_date("2026-07-01", train_end) == "validation"
    assert splits.split_for_date("2026-09-30", train_end) == "validation"
    assert splits.split_for_date("2026-10-01", train_end) == "test"
    assert splits.split_for_date("2026-12-31", train_end) == "test"


def test_no_future_leak_in_split_interactions():
    """Train interactions must never reference items aired after train_end."""
    train_end = dt.date(2025, 12, 31)
    air_dates = {1: "2025-01-15", 2: "2025-11-01", 3: "2026-02-01",
                 4: "2026-05-01", 5: "2026-07-01", 6: None}
    split_map = {sid: splits.split_for_date(d, train_end) for sid, d in air_dates.items()}

    # Simulate interaction rows assigned to the train split by item air date.
    train_rows = [sid for sid, s in split_map.items() if s == "train"]
    assert train_rows == [1, 2]
    # And the mirror: no train split item may appear in validation/test.
    for sid, s in split_map.items():
        if s in ("validation", "test"):
            assert sid not in train_rows
    # The no-date item is excluded entirely (cannot leak into train).
    assert split_map[6] is None


def test_item_classes():
    split_map = {
        1: "train", 2: "train", 3: "train",  # three train items
        4: "validation", 5: "test", 6: "validation",
        7: None,
    }
    train_counts = {1: 25, 2: 5, 3: 0}
    val_test_interacted = {4, 6}
    per_item = splits.compute_item_classes(split_map, train_counts, val_test_interacted)

    assert per_item[1] == ["warm_item"]          # > 20 train interactions
    assert per_item[2] == ["warm_item", "few_shot_item"]
    assert per_item[3] == ["train_zero_interaction"]
    assert per_item[4] == ["cold_item", "new_release"]
    assert per_item[5] == ["new_release"]        # aired in test quarter, no interactions yet
    assert 6 in per_item and "cold_item" in per_item[6]
    assert 7 not in per_item                      # no date -> no class


def test_item_class_counts_aggregate():
    split_map = {1: "train", 2: "train", 3: "validation", 4: "test", 5: "test"}
    train_counts = {1: 10}
    per_item = splits.compute_item_classes(split_map, train_counts, {3, 5})
    flat = [f for flags in per_item.values() for f in flags]
    assert flat.count("warm_item") == 1
    assert flat.count("few_shot_item") == 1
    assert flat.count("cold_item") == 2
    assert flat.count("new_release") == 3
    assert flat.count("train_zero_interaction") == 1
