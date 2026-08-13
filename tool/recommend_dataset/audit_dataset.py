#!/usr/bin/env python3
"""Aggregate-only audit for dataset completeness, coverage and long tails.

The report never includes usernames, anonymous user IDs or per-user rows.  It
opens the checkpoint database read-only and is safe to run before migrations.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

import pandas as pd

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from src import splits, weights
from src.config import load_config


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _quantiles(values: Iterable[int]) -> dict[str, float | int]:
    series = pd.Series(list(values), dtype="float64")
    if series.empty:
        return {
            "min": 0,
            "p10": 0.0,
            "p25": 0.0,
            "median": 0.0,
            "p75": 0.0,
            "p90": 0.0,
            "max": 0,
            "mean": 0.0,
        }
    return {
        "min": int(series.min()),
        "p10": round(float(series.quantile(0.10)), 3),
        "p25": round(float(series.quantile(0.25)), 3),
        "median": round(float(series.median()), 3),
        "p75": round(float(series.quantile(0.75)), 3),
        "p90": round(float(series.quantile(0.90)), 3),
        "max": int(series.max()),
        "mean": round(float(series.mean()), 3),
    }


def _status_counts(frame: pd.DataFrame, column: str) -> dict[str, int]:
    if frame.empty:
        return {}
    return {
        str(key): int(value)
        for key, value in frame[column].fillna("missing").value_counts().items()
    }


def build_audit(
    db_path: Path,
    *,
    train_end_date,
    page_size: int,
    legacy_page_cap: int,
    min_positive_interactions: int,
    core_min_item_support: int,
) -> dict:
    uri = f"file:{db_path.resolve().as_posix()}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    try:
        seed_columns = {
            str(row[1]) for row in conn.execute("PRAGMA table_info(seed_users)")
        }
        optional_seed_columns = [
            name
            for name in (
                "pages_fetched", "next_offset", "total_reported",
                "is_complete", "stop_reason",
            )
            if name in seed_columns
        ]
        seed = pd.read_sql_query(
            "SELECT status, items_fetched, anon_user_id"
            + (", " + ", ".join(optional_seed_columns) if optional_seed_columns else "")
            + " FROM seed_users",
            conn,
        )
        interactions = pd.read_sql_query(
            "SELECT i.anon_user_id, i.subject_id, i.collection_type, "
            "i.user_rating, i.updated_at, s.air_date, s.status AS subject_status "
            "FROM interactions i LEFT JOIN subjects s ON s.subject_id=i.subject_id",
            conn,
        )
        checkpoints = pd.read_sql_query(
            "SELECT key, value FROM checkpoints WHERE key LIKE 'collections:%:all'",
            conn,
        )
        subjects = pd.read_sql_query(
            "SELECT subject_id, status FROM subjects", conn
        )
        blocked = {
            int(row[0])
            for row in conn.execute(
                "SELECT subject_id FROM subjects WHERE status='permanent' "
                "UNION SELECT subject_id FROM known_subjects "
                "WHERE subject_type IS NOT NULL AND subject_type != 2"
            ).fetchall()
        }
    finally:
        conn.close()

    actual_counts = interactions.groupby("anon_user_id").size().to_dict()
    checkpoint_offsets: dict[str, int] = {}
    for row in checkpoints.itertuples(index=False):
        key = str(row.key)
        anonymous_id = key[len("collections:") : -len(":all")]
        try:
            checkpoint_offsets[anonymous_id] = int(row.value)
        except (TypeError, ValueError):
            continue

    ok = seed[seed["status"] == "ok"] if not seed.empty else seed
    actual_ok = [int(actual_counts.get(str(value), 0)) for value in ok["anon_user_id"]]
    mismatches = sum(
        int(row.items_fetched) != int(actual_counts.get(str(row.anon_user_id), 0))
        for row in ok.itertuples(index=False)
    )
    ok_offsets = [
        checkpoint_offsets.get(str(value)) for value in ok["anon_user_id"]
    ]
    present_offsets = [value for value in ok_offsets if value is not None]
    boundary_offsets = [
        value for value in present_offsets if value > 0 and value % page_size == 0
    ]

    eligible = interactions[~interactions["subject_id"].astype(int).isin(blocked)].copy()
    if not eligible.empty:
        eligible["is_negative"] = [
            weights.is_negative_feedback(int(row.collection_type), int(row.user_rating))
            for row in eligible.itertuples(index=False)
        ]
        eligible["feedback_tier"] = [
            weights.feedback_tier(int(row.collection_type), int(row.user_rating))
            for row in eligible.itertuples(index=False)
        ]
        split_values = [
            splits.interaction_split(
                row.updated_at, row.air_date, train_end_date
            )[0]
            for row in eligible.itertuples(index=False)
        ]
        eligible["split"] = split_values
        eligible["has_metadata"] = eligible["subject_status"] == "ok"
    else:
        eligible["is_negative"] = pd.Series(dtype=bool)
        eligible["split"] = pd.Series(dtype=str)
        eligible["has_metadata"] = pd.Series(dtype=bool)
        eligible["feedback_tier"] = pd.Series(dtype=str)

    positive = eligible[~eligible["is_negative"].astype(bool)]
    train_positive = positive[positive["split"] == splits.SPLIT_TRAIN]
    per_user = train_positive.groupby("anon_user_id").size()
    per_item = train_positive.groupby("subject_id").size()

    coverage_by_split: dict[str, dict[str, int | float]] = {}
    for split_name in (
        splits.SPLIT_TRAIN,
        splits.SPLIT_VALIDATION,
        splits.SPLIT_TEST,
    ):
        frame = positive[positive["split"] == split_name]
        covered = int(frame["has_metadata"].sum())
        total = int(len(frame))
        distinct_total = int(frame["subject_id"].nunique())
        distinct_covered = int(
            frame[frame["has_metadata"]]["subject_id"].nunique()
        )
        coverage_by_split[split_name] = {
            "positive_interactions": total,
            "covered_positive_interactions": covered,
            "interaction_coverage": round(covered / total, 6) if total else 0.0,
            "positive_items": distinct_total,
            "covered_positive_items": distinct_covered,
            "item_coverage": (
                round(distinct_covered / distinct_total, 6)
                if distinct_total
                else 0.0
            ),
        }

    support = per_item if not per_item.empty else pd.Series(dtype="int64")
    interaction_types = Counter(
        weights.COLLECTION_TYPE_NAME.get(int(value), str(value))
        for value in positive["collection_type"]
    )
    total_eligible = int(len(eligible))
    metadata_interactions = int(eligible["has_metadata"].sum())
    has_completion_state = "is_complete" in seed.columns
    complete_users = (
        int(seed["is_complete"].fillna(0).astype(int).sum())
        if has_completion_state
        else 0
    )
    incomplete_users = int(len(seed) - complete_users)
    complete_ids = (
        set(
            str(value)
            for value in seed[seed["is_complete"].fillna(0).astype(bool)]["anon_user_id"]
        )
        if has_completion_state
        else set()
    )
    complete_eligible = eligible[eligible["anon_user_id"].isin(complete_ids)]
    complete_positive = complete_eligible[
        ~complete_eligible["is_negative"].astype(bool)
    ]
    complete_train = complete_positive[
        complete_positive["split"] == splits.SPLIT_TRAIN
    ]
    complete_regular_train = complete_train[
        complete_train["feedback_tier"].isin(
            (weights.FEEDBACK_STRONG, weights.FEEDBACK_REGULAR)
        )
    ]
    complete_user_support = complete_regular_train.groupby("anon_user_id").size()
    qualified_complete_users = set(
        complete_user_support[
            complete_user_support >= min_positive_interactions
        ].index
    )
    qualified_complete_train = complete_regular_train[
        complete_regular_train["anon_user_id"].isin(qualified_complete_users)
    ]
    complete_item_support = qualified_complete_train.groupby("subject_id").size()
    complete_core_items = set(
        complete_item_support[
            complete_item_support >= core_min_item_support
        ].index
    )
    complete_core_train = qualified_complete_train[
        qualified_complete_train["subject_id"].isin(complete_core_items)
    ]

    return {
        "generated_at": _utcnow(),
        "database": {
            "bytes": db_path.stat().st_size,
            "seed_status": _status_counts(seed, "status"),
            "subject_status": _status_counts(subjects, "status"),
            "raw_interactions": int(len(interactions)),
            "blocked_interactions": int(len(interactions) - total_eligible),
            "eligible_interactions": total_eligible,
        },
        "legacy_collection_completeness": {
            "page_size": page_size,
            "legacy_page_cap": legacy_page_cap,
            "ok_users": int(len(ok)),
            "empty_users": int((seed["status"] == "empty").sum()),
            "ok_users_missing_checkpoint": sum(value is None for value in ok_offsets),
            "ok_users_with_non_boundary_final_page": sum(
                value is not None and value > 0 and value % page_size != 0
                for value in ok_offsets
            ),
            "ok_users_at_ambiguous_page_boundary": len(boundary_offsets),
            "suspected_truncated_at_legacy_cap": sum(
                value == legacy_page_cap for value in ok_offsets
            ),
            "items_fetched_mismatch_users": mismatches,
            "actual_interactions_per_ok_user": _quantiles(actual_ok),
            "checkpoint_offsets": _quantiles(present_offsets),
            "warning": (
                "Legacy status=ok does not prove completeness. Exact page-size "
                "boundaries are ambiguous because total and end-of-stream were "
                "not persisted; users at the legacy cap are suspected truncated."
            ),
        },
        "collection_completeness": {
            "state_schema_available": has_completion_state,
            "complete_users": complete_users,
            "incomplete_users": incomplete_users,
            "completion_ratio": (
                round(complete_users / len(seed), 6) if len(seed) else 0.0
            ),
            "complete_only_training_safe": has_completion_state and complete_users > 0,
            "complete_interactions": int(len(complete_eligible)),
            "complete_positive_train_users": int(
                complete_train["anon_user_id"].nunique()
            ),
            "complete_positive_train_interactions": int(len(complete_train)),
            "complete_regular_train_interactions": int(len(complete_regular_train)),
            "core_qualified_users": len(qualified_complete_users),
            "core_items": len(complete_core_items),
            "core_train_interactions": int(len(complete_core_train)),
            "core_min_user_interactions": min_positive_interactions,
            "core_min_item_support": core_min_item_support,
        },
        "training_distribution": {
            "positive_users": int(per_user.size),
            "positive_items": int(per_item.size),
            "positive_interactions": int(len(train_positive)),
            "interactions_per_user": _quantiles(per_user.tolist()),
            "support_per_item": _quantiles(per_item.tolist()),
            "users_lt_20": int((per_user < 20).sum()),
            "users_lt_50": int((per_user < 50).sum()),
            "items_support_eq_1": int((support == 1).sum()),
            "items_support_le_2": int((support <= 2).sum()),
            "items_support_lt_5": int((support < 5).sum()),
            "items_support_ge_20": int((support >= 20).sum()),
        },
        "feedback": {
            "positive_collection_types": dict(sorted(interaction_types.items())),
            "tiers": dict(sorted(Counter(
                weights.feedback_tier(int(row.collection_type), int(row.user_rating))
                for row in eligible.itertuples(index=False)
            ).items())),
            "negative_interactions": int(eligible["is_negative"].sum()),
            "unrated_interactions": int((eligible["user_rating"].fillna(0) <= 0).sum()),
            "unrated_ratio": (
                round(
                    float((eligible["user_rating"].fillna(0) <= 0).mean()), 6
                )
                if total_eligible
                else 0.0
            ),
        },
        "metadata": {
            "subjects_ok": int((subjects["status"] == "ok").sum()),
            "interaction_items": int(eligible["subject_id"].nunique()),
            "missing_distinct_items": int(
                eligible[~eligible["has_metadata"]]["subject_id"].nunique()
            ),
            "covered_interactions": metadata_interactions,
            "interaction_coverage": (
                round(metadata_interactions / total_eligible, 6)
                if total_eligible
                else 0.0
            ),
            "positive_coverage_by_split": coverage_by_split,
        },
        "temporal": {
            "split_counts": _status_counts(eligible, "split"),
            "train_leakage_rows": int(
                (
                    (eligible["split"] == splits.SPLIT_TRAIN)
                    & eligible["updated_at"].isna()
                ).sum()
            ),
        },
        "privacy": {
            "contains_usernames": False,
            "contains_anonymous_user_ids": False,
            "aggregate_only": True,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit recommendation dataset quality")
    parser.add_argument("--config", default="dataset_config.json")
    parser.add_argument("--output", default="")
    parser.add_argument(
        "--legacy-page-cap",
        type=int,
        default=200,
        help="historical per-user row boundary suspected of truncation",
    )
    args = parser.parse_args()

    cfg = load_config(args.config)
    report = build_audit(
        cfg.checkpoint_db,
        train_end_date=cfg.splits.train_end_date,
        page_size=cfg.interactions.page_size,
        legacy_page_cap=args.legacy_page_cap,
        min_positive_interactions=cfg.interactions.min_positive_interactions,
        core_min_item_support=cfg.interactions.core_min_item_support,
    )
    output = cfg.resolve(args.output) if args.output else cfg.data_dir / "dataset_audit.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    completeness = report["legacy_collection_completeness"]
    metadata = report["metadata"]
    print(
        f"[audit] ok_users={completeness['ok_users']} "
        f"suspected_truncated={completeness['suspected_truncated_at_legacy_cap']} "
        f"metadata_coverage={metadata['interaction_coverage']:.2%}"
    )
    print(f"[audit] report written to {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
