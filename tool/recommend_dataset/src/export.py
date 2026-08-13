"""Dataset export: CSV/JSONL outputs plus dataset_report.json.

Outputs (written under cfg.export_dir):
  subjects.csv                 - one row per collected anime subject (status=ok)
  interactions.csv             - master interaction table (positives AND negatives)
  train_interactions.csv       - positive samples only, split by updated_at
  validation_interactions.csv  - positive samples only
  test_interactions.csv        - positive samples only
  item_features.jsonl          - content features for cold-start modelling
  dataset_report.json          - coverage / class / split / fetch statistics

Interaction splits are strictly driven by interaction.updated_at (converted to
UTC); rows that are unassigned, future, or temporally invalid never enter any
split file. ALS interaction files may contain anime ids whose content metadata
has not been fetched yet. Content feature files still contain status='ok'
subjects only. Known non-anime and permanently unavailable ids are excluded.

No usernames, no salts, no tokens are ever written here: rows are keyed by
anonymous_user_id, and the report carries aggregate counts only.
"""
from __future__ import annotations

import datetime as dt
import json
import math
from pathlib import Path
from typing import Any, Optional

import pandas as pd

from src import parse, splits, weights
from src.db import Store
from src.model_views import cap_train_history

INTERACTION_MASTER_COLUMNS = [
    "anon_user_id", "subject_id", "collection_type", "collection_type_name",
    "user_rating", "updated_at", "fetched_at", "split", "split_reason",
    "collection_status", "collection_complete",
    "feedback_tier", "preference", "confidence_weight",
    "is_strong_positive", "is_weak_positive",
    "collection_weight", "rating_multiplier", "implicit_weight",
    "negative_weight", "is_negative",
]

SPLIT_COLUMNS = [
    "anon_user_id", "subject_id", "implicit_weight", "collection_type",
    "collection_type_name", "user_rating", "feedback_tier",
    "confidence_weight", "updated_at", "split",
]

SUBJECT_CSV_RENAME = {
    "tags_json": "tags",
    "meta_tags_json": "meta_tags",
    "infobox_json": "infobox",
}

COVERAGE_COLUMNS = [
    "name", "name_cn", "air_date", "platform", "episode_count", "summary",
    "tags", "meta_tags", "infobox", "score", "rank", "rating_total",
    "collection_total", "image_url", "production", "director",
    "series_composer", "original_work", "music", "voice_actors", "related",
]


def _json_safe(value: Any) -> Any:
    """Replace NaN/Infinity floats (pandas NULLs) with None recursively.

    json.dumps would otherwise emit bare NaN/Infinity tokens, which are not
    strict JSON and break jq / JSON.parse / Spark while Python's lenient
    json.loads silently accepts them.
    """
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    return value


def _count_train_after_cutoff(frame: pd.DataFrame, train_end_date: dt.date) -> int:
    """Train rows whose updated_at is missing or later than the cutoff.

    The split label itself derives from the same timestamp, so a label-based
    check can never fire; recompute the invariant from the raw timestamps.
    A nonzero count means leakage (splitter bug or corrupted data) reached
    the train view and blocks ALS readiness.
    """
    if frame.empty:
        return 0
    cutoff = splits.split_windows(train_end_date)["train_end"]
    leakage = 0
    for _, row in frame[frame["split"] == "train"].iterrows():
        parsed = splits.parse_iso_datetime(row["updated_at"])
        if parsed is None or parsed > cutoff:
            leakage += 1
    return leakage


def _load_json(value: Any) -> Any:
    if not value:
        return None
    if isinstance(value, (list, dict)):
        return value
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return None


def _non_empty(value: Any) -> bool:
    """True if a (parsed) field has real content."""
    if value is None:
        return False
    if isinstance(value, (list, dict)):
        return len(value) > 0
    text = str(value).strip()
    return text != "" and text.lower() != "nan"


SUBJECT_DF_COLUMNS = [
    "subject_id", "name", "name_cn", "air_date", "year", "season", "platform",
    "episode_count", "summary", "tags_json", "meta_tags_json", "infobox_json",
    "score", "rank", "rating_total", "collection_total",
    "wish_count", "doing_count", "collect_count", "on_hold_count", "dropped_count",
    "image_url", "production_json", "director_json", "series_composer_json",
    "original_work_json", "music_json", "voice_actors_json", "related_json",
    "persons_json", "nsfw", "fetched_at", "status", "error", "attempts",
]

INTERACTION_DF_COLUMNS = [
    "anon_user_id", "subject_id", "collection_type", "collection_type_name",
    "user_rating", "updated_at", "fetched_at",
]


def load_subjects_df(store: Store) -> pd.DataFrame:
    rows = store.list_subjects(statuses=("ok",))
    return pd.DataFrame(rows, columns=SUBJECT_DF_COLUMNS)


def load_interactions_df(store: Store) -> pd.DataFrame:
    rows = store.list_interactions()
    return pd.DataFrame(rows, columns=INTERACTION_DF_COLUMNS)


def build_export(store: Store, cfg: Any) -> dict[str, Any]:
    """Run the full export; returns the dataset_report content (also written)."""
    export_dir = cfg.export_dir
    export_dir.mkdir(parents=True, exist_ok=True)
    train_end = cfg.splits.train_end_date

    subjects = load_subjects_df(store)
    interactions = load_interactions_df(store)

    # ------------------------------------------------------------- validity
    if subjects.empty:
        valid_ids: set[int] = set()
    else:
        valid_ids = set(int(sid) for sid in subjects["subject_id"])
    blocked_ids = store.list_blocked_interaction_subject_ids()
    if interactions.empty:
        invalid_refs = 0
        blocked_interactions = 0
        valid_df = interactions.copy()
    else:
        sids = interactions["subject_id"].astype(int)
        invalid_mask = ~sids.isin(valid_ids)
        invalid_refs = int(invalid_mask.sum())
        blocked_mask = sids.isin(blocked_ids)
        blocked_interactions = int(blocked_mask.sum())
        valid_df = interactions[~blocked_mask].copy()

    # --------------------------------------------------------------- weights
    weight_rows: list[dict[str, Any]] = []
    for _, row in valid_df.iterrows():
        weight_rows.append(
            weights.classify_interaction(
                int(row["collection_type"] or 0), int(row["user_rating"] or 0)
            )
        )
    if weight_rows:
        wdf = pd.DataFrame(weight_rows)
    else:
        wdf = pd.DataFrame(
            columns=[
                "is_negative", "feedback_tier", "preference",
                "is_strong_positive", "is_weak_positive",
                "collection_weight", "rating_multiplier", "implicit_weight",
                "negative_weight", "confidence_weight",
            ]
        )
    master = pd.concat([valid_df.reset_index(drop=True), wdf.reset_index(drop=True)], axis=1)

    # Collection completeness is independent from an interaction's semantic
    # weight.  Keep every row in the master evidence table, while optionally
    # limiting model-ready views to users whose API stream reached its end.
    collection_states = store.user_collection_states()
    master["collection_status"] = [
        collection_states.get(str(value), {}).get("status", "unknown")
        for value in master["anon_user_id"]
    ]
    master["collection_complete"] = [
        bool(collection_states.get(str(value), {}).get("is_complete", False))
        for value in master["anon_user_id"]
    ]

    # ------------------------------------------- split assign (updated_at UTC)
    air_date_map: dict[int, Optional[str]] = {
        int(sid): None for sid in master["subject_id"].unique()
    } if not master.empty else {}
    for _, row in subjects.iterrows():
        air_date_map[int(row["subject_id"])] = row["air_date"]
    # Item-level air-date window (used only for new_release / unassigned_items).
    item_window_map: dict[int, Optional[str]] = {
        sid: splits.split_for_date(air_date_map[sid], train_end) for sid in air_date_map
    }

    split_rows: list[tuple[str, str]] = []
    for _, row in master.iterrows():
        split, reason = splits.interaction_split(
            row["updated_at"], air_date_map.get(int(row["subject_id"])), train_end
        )
        split_rows.append((split, reason))
    master["split"] = [s for s, _ in split_rows]
    master["split_reason"] = [r for _, r in split_rows]

    complete_only = bool(cfg.interactions.complete_only)
    training = (
        master[master["collection_complete"].astype(bool)].copy()
        if complete_only
        else master.copy()
    )
    training_before_cap = len(training)
    train_history_cap = int(cfg.interactions.max_train_interactions_per_user)
    training = cap_train_history(training, train_history_cap)
    capped_train_rows = training_before_cap - len(training)

    # ------------------------------------------------------------ item class
    train_counts: dict[int, int] = {}
    for _, row in training.iterrows():
        if row["split"] == "train" and not bool(row["is_negative"]):
            sid = int(row["subject_id"])
            train_counts[sid] = train_counts.get(sid, 0) + 1
    val_test_interacted: set[int] = set()
    for _, row in training.iterrows():
        if row["split"] in ("validation", "test") and not bool(row["is_negative"]):
            val_test_interacted.add(int(row["subject_id"]))
    per_item = splits.compute_item_flags(
        air_date_map, train_counts, val_test_interacted, train_end
    )
    class_counts: dict[str, int] = {
        "warm_item": 0, "few_shot_item": 0, "cold_item": 0,
        "new_release": 0, "train_zero_interaction": 0,
        "strict_cold_new_release": 0, "unknown_air_date": 0,
    }
    for flags in per_item.values():
        for flag in flags:
            class_counts[flag] += 1

    # ----------------------------------------------------------- split stats
    split_stats: dict[str, dict[str, int]] = {}
    for name in ("train", "validation", "test"):
        sub = training[(training["split"] == name) & (~training["is_negative"])]
        split_stats[name] = {
            "users": int(sub["anon_user_id"].nunique()) if not sub.empty else 0,
            "items": int(sub["subject_id"].nunique()) if not sub.empty else 0,
            "interactions": int(len(sub)),
        }
    model_users = split_stats["train"]["users"]

    # ------------------------------------------- temporal quality counters
    unassigned = int((training["split"] == "unassigned").sum())
    future = int((training["split"] == "future").sum())
    invalid_temporal = int((training["split"] == "invalid_temporal").sum())
    train_after_cutoff = _count_train_after_cutoff(training, train_end)

    # Model variants make feedback-strength and long-tail choices explicit.
    regular_tiers = {weights.FEEDBACK_STRONG, weights.FEEDBACK_REGULAR}
    regular = training[training["feedback_tier"].isin(regular_tiers)].copy()
    regular_train = regular[regular["split"] == "train"]
    minimum_user_interactions = int(cfg.interactions.min_positive_interactions)
    regular_user_counts = regular_train.groupby("anon_user_id").size()
    qualified_users = set(
        regular_user_counts[
            regular_user_counts >= minimum_user_interactions
        ].index
    )
    qualified_train = regular_train[regular_train["anon_user_id"].isin(qualified_users)]
    core_support = qualified_train.groupby("subject_id").size()
    minimum_item_support = int(cfg.interactions.core_min_item_support)
    core_items = set(core_support[core_support >= minimum_item_support].index)
    core = regular[
        regular["anon_user_id"].isin(qualified_users)
        & regular["subject_id"].isin(core_items)
    ].copy()

    variant_stats: dict[str, dict[str, dict[str, int]]] = {}
    variants = {
        "all_positive": training[~training["is_negative"].astype(bool)],
        "strong_positive": training[training["feedback_tier"] == weights.FEEDBACK_STRONG],
        "regular_positive": regular,
        "core": core,
    }
    for variant_name, frame in variants.items():
        variant_stats[variant_name] = {}
        for split_name in ("train", "validation", "test"):
            part = frame[frame["split"] == split_name]
            variant_stats[variant_name][split_name] = {
                "users": int(part["anon_user_id"].nunique()) if not part.empty else 0,
                "items": int(part["subject_id"].nunique()) if not part.empty else 0,
                "interactions": int(len(part)),
            }

    # ------------------------------------------------------------------ files
    subj_csv = subjects.rename(columns=SUBJECT_CSV_RENAME)
    subj_csv.to_csv(export_dir / "subjects.csv", index=False, encoding="utf-8")

    master[INTERACTION_MASTER_COLUMNS].to_csv(
        export_dir / "interactions.csv", index=False, encoding="utf-8"
    )
    for name in ("train", "validation", "test"):
        part = variants["all_positive"][variants["all_positive"]["split"] == name]
        part[SPLIT_COLUMNS].to_csv(
            export_dir / f"{name}_interactions.csv", index=False, encoding="utf-8"
        )
        for variant_name, file_label in (
            ("strong_positive", "strong"),
            ("regular_positive", "regular"),
            ("core", "core"),
        ):
            variant_part = variants[variant_name][
                variants[variant_name]["split"] == name
            ]
            variant_part[SPLIT_COLUMNS].to_csv(
                export_dir / f"{name}_{file_label}_interactions.csv",
                index=False,
                encoding="utf-8",
            )

    # item_features.jsonl
    feature_records: list[dict[str, Any]] = []
    for _, row in subjects.iterrows():
        sid = int(row["subject_id"])
        related = _load_json(row.get("related_json")) or []
        record = {
            "subject_id": sid,
            "name": row.get("name"),
            "name_cn": row.get("name_cn"),
            "air_date": row.get("air_date"),
            "year": row.get("year"),
            "season": row.get("season"),
            "season_name": parse.SEASON_NAMES.get(row.get("season") or 0, ""),
            "platform": row.get("platform"),
            "episode_count": row.get("episode_count"),
            "summary": row.get("summary"),
            "tags": _load_json(row.get("tags_json")) or [],
            "meta_tags": _load_json(row.get("meta_tags_json")) or [],
            "infobox": _load_json(row.get("infobox_json")) or {},
            "score": row.get("score"),
            "rank": row.get("rank"),
            "rating_total": row.get("rating_total"),
            "collection_total": row.get("collection_total"),
            "wish_count": row.get("wish_count"),
            "doing_count": row.get("doing_count"),
            "collect_count": row.get("collect_count"),
            "on_hold_count": row.get("on_hold_count"),
            "dropped_count": row.get("dropped_count"),
            "image_url": row.get("image_url"),
            "nsfw": bool(row.get("nsfw")),
            "production": _load_json(row.get("production_json")) or [],
            "director": _load_json(row.get("director_json")) or [],
            "series_composer": _load_json(row.get("series_composer_json")) or [],
            "original_work": _load_json(row.get("original_work_json")) or [],
            "music": _load_json(row.get("music_json")) or [],
            "voice_actors": _load_json(row.get("voice_actors_json")) or [],
            "related": related,
            "related_prequel_sequel": [
                r for r in related if parse.is_prequel_sequel(r.get("relation"))
            ],
            "air_date_window": item_window_map.get(sid),
            "flags": per_item.get(sid, []),
        }
        feature_records.append(record)
    with (export_dir / "item_features.jsonl").open("w", encoding="utf-8") as handle:
        for record in feature_records:
            # Escape U+2028/U+2029: Python's json leaves them raw, but they are
            # line separators - any line-based reader would split the record.
            line = json.dumps(_json_safe(record), ensure_ascii=False)
            line = line.replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
            handle.write(line + "\n")

    # ---------------------------------------------------------------- report
    master_users = int(master["anon_user_id"].nunique()) if not master.empty else 0
    master_items = int(master["subject_id"].nunique()) if not master.empty else 0
    users = int(training["anon_user_id"].nunique()) if not training.empty else 0
    items = int(training["subject_id"].nunique()) if not training.empty else 0
    total_interactions = int(len(master))
    sparsity = (
        1.0 - (total_interactions / (master_users * master_items))
        if master_users and master_items
        else 1.0
    )

    coverage: dict[str, float] = {}
    n_subjects = len(subjects)
    for col in COVERAGE_COLUMNS:
        db_col = {
            "tags": "tags_json", "meta_tags": "meta_tags_json",
            "infobox": "infobox_json", "production": "production_json",
            "director": "director_json", "series_composer": "series_composer_json",
            "original_work": "original_work_json", "music": "music_json",
            "voice_actors": "voice_actors_json", "related": "related_json",
        }.get(col, col)
        if col in ("tags", "meta_tags", "infobox", "production", "director",
                   "series_composer", "original_work", "music", "voice_actors", "related"):
            values = [_non_empty(_load_json(row.get(db_col))) for _, row in subjects.iterrows()]
        else:
            values = [_non_empty(row.get(db_col)) for _, row in subjects.iterrows()]
        coverage[col] = round(sum(values) / n_subjects, 4) if n_subjects else 0.0

    by_type: dict[str, int] = {}
    if not master.empty:
        for _, row in master.iterrows():
            name = weights.COLLECTION_TYPE_NAME.get(int(row["collection_type"]), "unknown")
            by_type[name] = by_type.get(name, 0) + 1
    rated = int((master["user_rating"].astype(int) > 0).sum()) if not master.empty else 0
    feedback_tiers = {
        str(name): int(count)
        for name, count in master["feedback_tier"].value_counts().items()
    } if not master.empty else {}

    failed_log = Path(cfg.failed_requests)
    failed_entries = 0
    if failed_log.exists():
        failed_entries = sum(1 for _ in failed_log.open(encoding="utf-8"))

    # Temporal quality over the RAW interaction table (not just valid refs).
    raw_updated_coverage = 0
    for _, row in interactions.iterrows():
        if splits.parse_iso_datetime(row["updated_at"]) is not None:
            raw_updated_coverage += 1
    updated_at_coverage = (
        round(raw_updated_coverage / len(interactions), 4) if len(interactions) else 0.0
    )

    reference_ids = set(int(sid) for sid in interactions["subject_id"]) if not interactions.empty else set()
    missing_distinct = len(reference_ids - valid_ids)
    total_raw = int(len(interactions))
    subject_reference_coverage = (
        round(1.0 - invalid_refs / total_raw, 4) if total_raw else 0.0
    )

    # Readiness is layered: ALS only needs interaction scale and clean temporal
    # splits; hybrid evaluation additionally needs content metadata coverage.
    train_positives = split_stats["train"]["interactions"]
    ready_content = n_subjects > 0 and model_users > 0 and train_positives > 0
    blockers: list[str] = []
    if n_subjects == 0:
        blockers.append("no subjects collected")
    if model_users == 0:
        blockers.append("no valid users")
    if train_positives == 0:
        blockers.append("no positive train interactions")
    if split_stats["validation"]["interactions"] == 0:
        blockers.append("no validation interactions")
    if split_stats["test"]["interactions"] == 0:
        blockers.append("no test interactions")

    val_ids = {
        int(row["subject_id"])
        for _, row in training.iterrows()
        if row["split"] == "validation" and not bool(row["is_negative"])
    }
    cold_val_items = sum(
        1 for sid in val_ids if train_counts.get(sid, 0) == 0
    )
    test_ids = {
        int(row["subject_id"])
        for _, row in training.iterrows()
        if row["split"] == "test" and not bool(row["is_negative"])
    }
    cold_test_items = sum(
        1 for sid in test_ids if train_counts.get(sid, 0) == 0
    )
    content_cold_val_items = sum(
        1 for sid in val_ids if sid in valid_ids and train_counts.get(sid, 0) == 0
    )
    content_cold_test_items = sum(
        1 for sid in test_ids if sid in valid_ids and train_counts.get(sid, 0) == 0
    )

    als_thresholds = {
        "valid_users_ge": 500,
        "positive_train_interactions_ge": 50000,
        "validation_interactions_gt": 0,
        "test_interactions_gt": 0,
        "temporal_leakage_rows_eq": 0,
    }
    als_checks = [
        model_users >= als_thresholds["valid_users_ge"],
        train_positives >= als_thresholds["positive_train_interactions_ge"],
        split_stats["validation"]["interactions"] > 0,
        split_stats["test"]["interactions"] > 0,
        train_after_cutoff == 0,
    ]
    als_blockers: list[str] = []
    if model_users < als_thresholds["valid_users_ge"]:
        als_blockers.append(
            f"valid_users {model_users} < {als_thresholds['valid_users_ge']}"
        )
    if train_positives < als_thresholds["positive_train_interactions_ge"]:
        als_blockers.append(
            f"positive_train_interactions {train_positives} < "
            f"{als_thresholds['positive_train_interactions_ge']}"
        )
    if split_stats["validation"]["interactions"] == 0:
        als_blockers.append("validation_interactions == 0")
    if split_stats["test"]["interactions"] == 0:
        als_blockers.append("test_interactions == 0")
    if train_after_cutoff != 0:
        als_blockers.append(f"temporal_leakage_rows {train_after_cutoff} != 0")

    hybrid_thresholds = {
        "content_cold_validation_items_ge": 100,
        "content_cold_test_items_ge": 100,
    }
    hybrid_blockers = list(als_blockers)
    if content_cold_val_items < hybrid_thresholds["content_cold_validation_items_ge"]:
        hybrid_blockers.append(
            f"content_cold_validation_items {content_cold_val_items} < "
            f"{hybrid_thresholds['content_cold_validation_items_ge']}"
        )
    if content_cold_test_items < hybrid_thresholds["content_cold_test_items_ge"]:
        hybrid_blockers.append(
            f"content_cold_test_items {content_cold_test_items} < "
            f"{hybrid_thresholds['content_cold_test_items_ge']}"
        )

    strict = bool(getattr(cfg, "evaluation", None) and cfg.evaluation.strict_temporal)

    report: dict[str, Any] = {
        "generated_at": _utcnow(),
        "config": {
            "train_end_date": train_end.isoformat(),
            "api_base_url": cfg.api.base_url,
            "qps": cfg.api.qps,
            "max_concurrency": cfg.api.max_concurrency,
            "complete_only": complete_only,
            "min_positive_interactions": minimum_user_interactions,
            "core_min_item_support": minimum_item_support,
            "max_train_interactions_per_user": train_history_cap,
        },
        "subjects": {
            "total": n_subjects,
            "with_air_date": int(round(coverage["air_date"] * n_subjects)),
        },
        "interactions": {
            "total_raw": total_raw,
            "total": total_interactions,
            "invalid_refs": invalid_refs,
            "blocked_interactions": blocked_interactions,
            "subject_reference_coverage": subject_reference_coverage,
            "missing_distinct_subjects": missing_distinct,
            "users": master_users,
            "items": master_items,
            "sparsity": round(sparsity, 6),
            "rated_ratio": round(rated / total_interactions, 4) if total_interactions else 0.0,
            "by_collection_type": by_type,
            "by_feedback_tier": feedback_tiers,
            "training_eligible": int(len(training)),
            "training_users": users,
            "training_items": items,
            "train_positive_users": model_users,
            "train_rows_removed_by_user_cap": capped_train_rows,
        },
        "coverage": coverage,
        "splits": split_stats,
        "model_views": {
            "variants": variant_stats,
            "core": {
                "qualified_users": len(qualified_users),
                "eligible_items": len(core_items),
                "min_user_train_interactions": minimum_user_interactions,
                "min_item_train_support": minimum_item_support,
            },
        },
        "unassigned_items": sum(1 for s in item_window_map.values() if s is None),
        "item_classes": class_counts,
        "temporal_quality": {
            "updated_at_coverage": updated_at_coverage,
            "unassigned_interactions": unassigned,
            "future_interactions": future,
            "invalid_temporal_interactions": invalid_temporal,
            "train_interactions_after_cutoff": train_after_cutoff,
        },
        "evaluation": {
            "strict_temporal": strict,
            "potential_feature_leakage": bool(
                getattr(cfg, "evaluation", None)
                and cfg.evaluation.allow_dynamic_popularity_features
            ),
        },
        "readiness": {
            "ready_for_content_baseline": ready_content,
            "ready_for_als": all(als_checks),
            "ready_for_hybrid": not hybrid_blockers,
            "blockers": blockers,
            "als_blockers": als_blockers,
            "hybrid_blockers": hybrid_blockers,
            "als_thresholds": als_thresholds,
            "hybrid_thresholds": hybrid_thresholds,
            "metadata_coverage_advisory": {
                "actual": subject_reference_coverage,
                "target": 0.98,
                "target_met": subject_reference_coverage >= 0.98,
            },
            "cold_validation_items": cold_val_items,
            "cold_test_items": cold_test_items,
            "content_cold_validation_items": content_cold_val_items,
            "content_cold_test_items": content_cold_test_items,
        },
        "duplicates": {
            "subjects_updated": store.meta_value("subjects_updated"),
            "interactions_updated": store.meta_value("interactions_updated"),
        },
        "fetch": {
            "subjects_stage": store.aggregate_stats("subjects"),
            "interactions_stage": store.aggregate_stats("interactions"),
            "failed_request_log_entries": failed_entries,
        },
        "seed_users": _seed_users(store),
    }
    report["files"] = sorted(p.name for p in export_dir.iterdir() if p.is_file())
    with (export_dir / "dataset_report.json").open("w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
    return report


def _seed_users(store: Store) -> dict[str, int]:
    summary = store.seed_user_summary()
    counts: dict[str, int] = {
        "requested": 0,
        "complete": 0,
        "empty": 0,
        "truncated": 0,
        "unavailable": 0,
        "error": 0,
        "pending": 0,
        "legacy_ok_unverified": 0,
    }
    for status, count in summary.items():
        if status == "ok":
            counts["legacy_ok_unverified"] += count
        elif status in counts:
            counts[status] = count
        else:
            counts["pending"] += count
    completeness = store.seed_user_completeness_summary()
    counts["requested"] = completeness["requested"]
    counts["collection_complete"] = completeness["complete"]
    counts["collection_incomplete"] = completeness["incomplete"]
    return counts


def _utcnow() -> str:
    import datetime as dt

    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
