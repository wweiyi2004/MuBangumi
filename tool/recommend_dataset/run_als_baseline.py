#!/usr/bin/env python3
"""Train and evaluate the first reproducible implicit-ALS baseline.

Protocol:
1. Fit fixed positive-only and signed-negative variants on the train window.
2. Select by validation NDCG@10 only.
3. Refit the selected variant on train + validation.
4. Evaluate once on the test window and persist the model plus ID maps.

Candidate catalogs observe the global timeline.  An item is eligible when it
was already present in the history matrix or has a known air date no later
than the evaluation cutoff.  Each user excludes only their own history.
"""
from __future__ import annotations

import json
import sys
import time
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from baseline import metrics as mt
from baseline.als_model import (
    IdMaps,
    build_confidence_matrix,
    fit_als,
    rank_user,
    save_model,
)
from run_content_baseline import load_items_df, load_master_df
from src.config import load_config
from src.model_views import cap_train_history
from src.parse import parse_date_flexible
from src.splits import split_windows


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _positive(frame: pd.DataFrame) -> pd.DataFrame:
    return frame[~frame["is_negative"].astype(bool)]


def selection_metric_key(top_k: list[int]) -> str:
    """Primary validation metric key used for variant selection.

    The frozen protocol selects on NDCG@10; whenever 10 is among the
    configured top_k values that exact key is kept.  Otherwise the largest
    configured k is used, so variant scores never silently collapse to 0.
    """
    if not top_k:
        return "ndcg@10"
    k = 10 if 10 in top_k else max(top_k)
    return f"ndcg@{k}"


def select_model_view(
    export_dir: Path,
    master: pd.DataFrame,
    *,
    complete_only: bool,
    view: str,
    max_train_interactions_per_user: int = 0,
) -> pd.DataFrame:
    """Load one explicit feedback/completeness view for ALS."""
    if view == "all":
        selected = master.copy()
        if complete_only:
            if "collection_complete" not in selected.columns:
                raise ValueError(
                    "complete_only requires collection_complete in interactions.csv; "
                    "rerun export_dataset.py"
                )
            selected = selected[selected["collection_complete"].astype(bool)].copy()
        return cap_train_history(selected, max_train_interactions_per_user)

    label = {"regular": "regular", "core": "core"}[view]
    parts: list[pd.DataFrame] = []
    for split_name in ("train", "validation", "test"):
        path = export_dir / f"{split_name}_{label}_interactions.csv"
        if not path.exists():
            raise ValueError(f"model view file missing; rerun export_dataset.py: {path}")
        part = pd.read_csv(path)
        part["is_negative"] = False
        part["negative_weight"] = 0.0
        parts.append(part)
    return pd.concat(parts, ignore_index=True)


def _owned_by_user(frame: pd.DataFrame) -> dict[str, set[int]]:
    if frame.empty:
        return {}
    return {
        str(user_id): set(int(value) for value in group["subject_id"])
        for user_id, group in frame.groupby("anon_user_id", sort=False)
    }


def _positive_users(frame: pd.DataFrame) -> set[str]:
    return set(str(value) for value in _positive(frame)["anon_user_id"].unique())


def _metadata_catalog(items: pd.DataFrame, window_end: date) -> set[int]:
    result: set[int] = set()
    for _, row in items.iterrows():
        nsfw = row.get("nsfw", False)
        if not pd.isna(nsfw) and bool(nsfw):
            continue
        air_date = parse_date_flexible(row.get("air_date"))
        if air_date is None or air_date > window_end:
            continue
        result.add(int(row["subject_id"]))
    return result


def candidate_catalogs(
    items: pd.DataFrame,
    history: pd.DataFrame,
    maps: IdMaps,
    window_end: date,
) -> dict[str, list[int]]:
    """Build leakage-safe interaction and content candidate catalogs."""
    known_items = set(int(value) for value in history["subject_id"].unique())
    content_items = _metadata_catalog(items, window_end)
    model_items = set(int(value) for value in maps.subject_ids)
    return {
        "interaction": sorted((known_items | content_items) & model_items),
        "content": sorted(content_items & model_items),
    }


def _popularity_ranking(candidates: list[int], history: pd.DataFrame) -> list[int]:
    counts = _positive(history).groupby("subject_id").size().to_dict()
    return sorted(candidates, key=lambda sid: (-counts.get(int(sid), 0), int(sid)))


def evaluate_group(
    relevant_df: pd.DataFrame,
    candidates: list[int],
    history: pd.DataFrame,
    model: Any,
    maps: IdMaps,
    top_k: list[int],
) -> dict[str, Any]:
    """Evaluate ALS and popularity over per-user full catalogs."""
    raw_users = int(relevant_df["anon_user_id"].nunique()) if not relevant_df.empty else 0
    raw_positives = int(len(relevant_df))
    if relevant_df.empty or not candidates:
        return {
            "status": "insufficient_data",
            "raw_users": raw_users,
            "raw_positives": raw_positives,
            "users": 0,
            "eligible_positives": 0,
            "candidate_items": len(candidates),
            "models": {},
        }

    candidate_set = set(candidates)
    owned = _owned_by_user(history)
    profile_users = _positive_users(history)
    relevant_by_user: dict[str, set[int]] = {}
    for row in relevant_df.itertuples(index=False):
        user_id = str(row.anon_user_id)
        subject_id = int(row.subject_id)
        if (
            user_id in profile_users
            and user_id in maps.user_index
            and subject_id in candidate_set
            and subject_id not in owned.get(user_id, set())
        ):
            relevant_by_user.setdefault(user_id, set()).add(subject_id)

    if not relevant_by_user:
        return {
            "status": "insufficient_data",
            "raw_users": raw_users,
            "raw_positives": raw_positives,
            "users": 0,
            "eligible_positives": 0,
            "candidate_items": len(candidates),
            "models": {},
        }

    popularity = _popularity_ranking(candidates, history)
    max_k = max(top_k)
    als_rows: list[dict[str, float]] = []
    pop_rows: list[dict[str, float]] = []
    als_ranked_lists: list[list[int]] = []
    pop_ranked_lists: list[list[int]] = []
    candidate_counts: list[int] = []

    for user_id in sorted(relevant_by_user):
        excluded = owned.get(user_id, set())
        relevant = relevant_by_user[user_id]
        als_ranked = rank_user(
            model, maps, user_id, candidates, excluded, max_k
        )
        pop_ranked = [
            subject_id for subject_id in popularity if subject_id not in excluded
        ][:max_k]
        als_rows.append(mt.per_user_metrics(als_ranked, relevant, top_k))
        pop_rows.append(mt.per_user_metrics(pop_ranked, relevant, top_k))
        als_ranked_lists.append(als_ranked)
        pop_ranked_lists.append(pop_ranked)
        candidate_counts.append(len(candidate_set - excluded))

    return {
        "status": "ok",
        "raw_users": raw_users,
        "raw_positives": raw_positives,
        "users": len(relevant_by_user),
        "eligible_positives": sum(len(value) for value in relevant_by_user.values()),
        "candidate_items": len(candidates),
        "mean_candidates_per_user": round(float(np.mean(candidate_counts)), 2),
        "models": {
            "implicit_als": {
                **mt.mean_metrics(als_rows, top_k),
                "catalog_coverage": mt.catalog_coverage_at_k(
                    als_ranked_lists, len(candidates), max_k
                ),
            },
            "popularity_baseline": {
                **mt.mean_metrics(pop_rows, top_k),
                "catalog_coverage": mt.catalog_coverage_at_k(
                    pop_ranked_lists, len(candidates), max_k
                ),
            },
        },
    }


def _air_dates(items: pd.DataFrame) -> dict[int, date]:
    result: dict[int, date] = {}
    for _, row in items.iterrows():
        parsed = parse_date_flexible(row.get("air_date"))
        if parsed is not None:
            result[int(row["subject_id"])] = parsed
    return result


def evaluate_window(
    split_name: str,
    relevant_df: pd.DataFrame,
    history: pd.DataFrame,
    candidates: dict[str, list[int]],
    model: Any,
    maps: IdMaps,
    top_k: list[int],
    air_dates: dict[int, date],
    window_start: date,
    window_end: date,
) -> dict[str, Any]:
    positives = _positive(relevant_df)
    warm_ids = set(int(value) for value in _positive(history)["subject_id"].unique())
    relevant_ids = set(int(value) for value in positives["subject_id"].unique())
    cold_ids = relevant_ids - warm_ids
    strict_cold_ids = {
        subject_id
        for subject_id in cold_ids
        if subject_id in air_dates
        and window_start < air_dates[subject_id] <= window_end
    }

    groups = {
        f"{split_name}_all": (positives, candidates["interaction"]),
        f"{split_name}_warm_item": (
            positives[positives["subject_id"].astype(int).isin(warm_ids)],
            candidates["interaction"],
        ),
        f"{split_name}_cold_item": (
            positives[positives["subject_id"].astype(int).isin(cold_ids)],
            candidates["interaction"],
        ),
        f"{split_name}_strict_cold_new_release": (
            positives[positives["subject_id"].astype(int).isin(strict_cold_ids)],
            candidates["interaction"],
        ),
        f"{split_name}_content_catalog": (positives, candidates["content"]),
    }
    return {
        name: evaluate_group(frame, catalog, history, model, maps, top_k)
        for name, (frame, catalog) in groups.items()
    }


def _train_variant(
    history: pd.DataFrame,
    maps: IdMaps,
    cfg: Any,
    negative_scale: float,
    random_seed: int,
    recency_half_life_days: float = 0.0,
    reference_time: Any = None,
) -> tuple[Any, Any, float]:
    confidence = build_confidence_matrix(
        history,
        maps,
        negative_scale=negative_scale,
        recency_half_life_days=recency_half_life_days,
        reference_time=reference_time,
    )
    started = time.perf_counter()
    model = fit_als(confidence, cfg, random_seed=random_seed)
    elapsed = time.perf_counter() - started
    return model, confidence, elapsed


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Train the first implicit ALS baseline")
    parser.add_argument("--config", default="dataset_config.json")
    parser.add_argument(
        "--view",
        choices=("all", "regular", "core"),
        default="all",
        help="feedback/completeness view produced by export_dataset.py",
    )
    parser.add_argument(
        "--negative-scale",
        type=float,
        default=None,
        help="fixed negative scale selected externally (for example by run_als_cv.py)",
    )
    parser.add_argument(
        "--recency-half-life-days",
        type=float,
        default=None,
        help="fixed fold-local confidence half-life; 0 disables recency decay",
    )
    args = parser.parse_args()
    if args.negative_scale is not None and args.negative_scale < 0:
        parser.error("--negative-scale must be >= 0")
    if args.recency_half_life_days is not None and args.recency_half_life_days < 0:
        parser.error("--recency-half-life-days must be >= 0")

    cfg = load_config(args.config)
    raw_master = load_master_df(cfg.export_dir)
    items = load_items_df(cfg.export_dir)
    if raw_master.empty:
        raise SystemExit(f"interactions.csv missing or empty: {cfg.export_dir}")
    try:
        master = select_model_view(
            cfg.export_dir,
            raw_master,
            complete_only=cfg.interactions.complete_only,
            view=args.view,
            max_train_interactions_per_user=(
                cfg.interactions.max_train_interactions_per_user
            ),
        )
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
    if master.empty:
        raise SystemExit(f"ALS view {args.view!r} is empty: {cfg.export_dir}")

    maps = IdMaps.from_interactions(master)
    train = master[master["split"] == "train"].copy()
    validation = master[master["split"] == "validation"].copy()
    test = master[master["split"] == "test"].copy()
    if train.empty or validation.empty or test.empty:
        raise SystemExit("train, validation and test windows must all be non-empty")

    windows = split_windows(cfg.splits.train_end_date)
    validation_start = cfg.splits.train_end_date
    validation_end = windows["validation_end"].date()
    test_start = validation_end
    test_end = windows["test_end"].date()
    air_dates = _air_dates(items)
    validation_catalogs = candidate_catalogs(items, train, maps, validation_end)
    if args.view != "all":
        negative_scales = [0.0]
    elif args.negative_scale is not None:
        negative_scales = [args.negative_scale]
    else:
        negative_scales = cfg.als_model.negative_scales
    recency_half_life_days = (
        cfg.als_model.recency_half_life_days
        if args.recency_half_life_days is None
        else args.recency_half_life_days
    )

    metric_key = selection_metric_key(cfg.evaluation.top_k)
    report: dict[str, Any] = {
        "generated_at": _utcnow(),
        "protocol": {
            "selection_metric": (
                "fixed_external_negative_scale"
                if args.negative_scale is not None
                else f"validation_all.implicit_als.{metric_key}"
            ),
            "test_locked_until_after_variant_selection": True,
            "candidate_policy": (
                "global time-safe catalog; exclude only each user's own history"
            ),
            "random_seed": cfg.evaluation.random_seed,
            "model_view": args.view,
            "complete_only": cfg.interactions.complete_only,
        },
        "config": {
            "factors": cfg.als_model.factors,
            "regularization": cfg.als_model.regularization,
            "alpha": cfg.als_model.alpha,
            "iterations": cfg.als_model.iterations,
            "negative_scales": negative_scales,
            "recency_half_life_days": recency_half_life_days,
        },
        "data_summary": {
            "users": len(maps.user_ids),
            "items": len(maps.subject_ids),
            "train_rows": len(train),
            "validation_rows": len(validation),
            "test_rows": len(test),
            "validation_interaction_candidates": len(
                validation_catalogs["interaction"]
            ),
            "validation_content_candidates": len(validation_catalogs["content"]),
        },
        "validation_variants": {},
    }

    scored_variants: list[tuple[float, float]] = []
    for negative_scale in negative_scales:
        label = f"negative_scale_{negative_scale:g}"
        print(f"[als] training validation variant {label}", flush=True)
        model, confidence, elapsed = _train_variant(
            train,
            maps,
            cfg.als_model,
            negative_scale,
            cfg.evaluation.random_seed,
            recency_half_life_days,
            cfg.splits.train_end_date,
        )
        groups = evaluate_window(
            "validation",
            validation,
            train,
            validation_catalogs,
            model,
            maps,
            cfg.evaluation.top_k,
            air_dates,
            validation_start,
            validation_end,
        )
        primary = groups["validation_all"]
        score = float(primary.get("models", {}).get("implicit_als", {}).get(metric_key, 0.0))
        scored_variants.append((score, negative_scale))
        report["validation_variants"][label] = {
            "negative_scale": negative_scale,
            "matrix_nnz": int(confidence.nnz),
            "training_seconds": round(elapsed, 3),
            "selection_score": score,
            "groups": groups,
        }
        print(f"[als] {label} validation {metric_key}={score:.6f}", flush=True)

    # Stable tie break prefers the simpler, smaller negative scale.
    selected_score, selected_scale = max(
        scored_variants, key=lambda pair: (pair[0], -pair[1])
    )
    report["selection"] = {
        "negative_scale": selected_scale,
        "validation_ndcg@10": selected_score,
        "source": "external" if args.negative_scale is not None else "validation",
    }

    final_history = pd.concat([train, validation], ignore_index=True)
    print(
        f"[als] selected negative_scale={selected_scale:g}; "
        "refitting train+validation",
        flush=True,
    )
    final_model, final_confidence, elapsed = _train_variant(
        final_history,
        maps,
        cfg.als_model,
        selected_scale,
        cfg.evaluation.random_seed,
        recency_half_life_days,
        validation_end,
    )
    test_catalogs = candidate_catalogs(items, final_history, maps, test_end)
    test_groups = evaluate_window(
        "test",
        test,
        final_history,
        test_catalogs,
        final_model,
        maps,
        cfg.evaluation.top_k,
        air_dates,
        test_start,
        test_end,
    )
    report["final_fit"] = {
        "history_rows": len(final_history),
        "matrix_nnz": int(final_confidence.nnz),
        "training_seconds": round(elapsed, 3),
        "test_interaction_candidates": len(test_catalogs["interaction"]),
        "test_content_candidates": len(test_catalogs["content"]),
    }
    report["test_groups"] = test_groups

    output_dir = cfg.als_dir if args.view == "all" else cfg.als_dir / args.view
    output_dir.mkdir(parents=True, exist_ok=True)
    save_model(
        final_model,
        maps,
        output_dir,
        {
            "generated_at": report["generated_at"],
            "negative_scale": selected_scale,
            **report["config"],
            "history": "train+validation",
        },
    )
    report_path = output_dir / "als_report.json"
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    for group_name, group in test_groups.items():
        if group["status"] != "ok":
            print(f"[als] {group_name}: insufficient_data")
            continue
        als = group["models"]["implicit_als"]
        pop = group["models"]["popularity_baseline"]
        print(
            f"[als] {group_name}: users={group['users']} "
            f"candidates={group['candidate_items']} "
            f"ndcg@10 als={als.get('ndcg@10')} pop={pop.get('ndcg@10')} "
            f"recall@20 als={als.get('recall@20')} pop={pop.get('recall@20')}",
            flush=True,
        )
    print(f"[als] report written to {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
