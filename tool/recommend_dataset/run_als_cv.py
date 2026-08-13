#!/usr/bin/env python3
"""Rolling-origin temporal cross-validation for the implicit ALS model.

The folds are historical quarter boundaries.  Every fold trains on data at or
before its cutoff and validates on the following natural quarter.  No test
window is used for hyperparameter selection.
"""
from __future__ import annotations

import argparse
import itertools
import json
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from baseline.als_model import IdMaps
from run_als_baseline import (
    _air_dates,
    _positive,
    _train_variant,
    candidate_catalogs,
    evaluate_group,
    select_model_view,
    selection_metric_key,
)
from run_content_baseline import load_items_df, load_master_df
from src import splits, weights
from src.config import load_config
from src.model_views import cap_train_history


DEFAULT_CUTOFFS = (date(2025, 6, 30), date(2025, 9, 30), date(2025, 12, 31))


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def build_fold(
    master: pd.DataFrame,
    air_dates: dict[int, date],
    cutoff: date,
    cfg: Any,
    view: str,
) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, int]]:
    assigned = master.copy()
    assigned["cv_split"] = [
        splits.interaction_split(
            row.updated_at,
            air_dates.get(int(row.subject_id)).isoformat()
            if int(row.subject_id) in air_dates
            else None,
            cutoff,
        )[0]
        for row in assigned.itertuples(index=False)
    ]
    fold = assigned[assigned["cv_split"].isin(("train", "validation"))].copy()
    fold = cap_train_history(
        fold,
        cfg.interactions.max_train_interactions_per_user,
        split_column="cv_split",
    )

    if view in ("regular", "core"):
        fold = fold[fold["feedback_tier"].isin(
            (weights.FEEDBACK_STRONG, weights.FEEDBACK_REGULAR)
        )].copy()

    qualified_users: set[str] = set(str(value) for value in fold["anon_user_id"].unique())
    core_items: set[int] = set(int(value) for value in fold["subject_id"].unique())
    if view == "core":
        train_regular = fold[fold["cv_split"] == "train"]
        per_user = train_regular.groupby("anon_user_id").size()
        qualified_users = set(
            str(value)
            for value in per_user[
                per_user >= cfg.interactions.min_positive_interactions
            ].index
        )
        qualified_train = train_regular[
            train_regular["anon_user_id"].isin(qualified_users)
        ]
        per_item = qualified_train.groupby("subject_id").size()
        core_items = set(
            int(value)
            for value in per_item[
                per_item >= cfg.interactions.core_min_item_support
            ].index
        )
        fold = fold[
            fold["anon_user_id"].isin(qualified_users)
            & fold["subject_id"].isin(core_items)
        ].copy()

    train = fold[fold["cv_split"] == "train"].copy()
    validation = fold[fold["cv_split"] == "validation"].copy()
    return train, validation, {
        "qualified_users": len(qualified_users),
        "core_items": len(core_items),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Rolling temporal CV for implicit ALS")
    parser.add_argument("--config", default="dataset_config.json")
    parser.add_argument("--view", choices=("all", "regular", "core"), default="all")
    parser.add_argument(
        "--cutoffs",
        nargs="*",
        default=[value.isoformat() for value in DEFAULT_CUTOFFS],
        help="rolling train cutoffs in YYYY-MM-DD form",
    )
    parser.add_argument(
        "--negative-scales",
        nargs="*",
        type=float,
        default=None,
        help="override configured negative scales",
    )
    parser.add_argument(
        "--half-lives",
        nargs="*",
        type=float,
        default=None,
        help="recency confidence half-lives in days; 0 disables decay",
    )
    parser.add_argument("--factors", nargs="*", type=int, default=None)
    parser.add_argument("--regularizations", nargs="*", type=float, default=None)
    parser.add_argument("--alphas", nargs="*", type=float, default=None)
    parser.add_argument(
        "--report-name",
        default="als_cv_report.json",
        help="output filename inside the selected ALS directory",
    )
    args = parser.parse_args()
    if args.negative_scales is not None and (
        not args.negative_scales or any(value < 0 for value in args.negative_scales)
    ):
        parser.error("--negative-scales requires one or more values >= 0")
    if args.half_lives is not None and (
        not args.half_lives or any(value < 0 for value in args.half_lives)
    ):
        parser.error("--half-lives requires one or more values >= 0")
    if args.factors is not None and (
        not args.factors or any(value < 1 for value in args.factors)
    ):
        parser.error("--factors requires one or more values >= 1")
    if args.regularizations is not None and (
        not args.regularizations or any(value < 0 for value in args.regularizations)
    ):
        parser.error("--regularizations requires one or more values >= 0")
    if args.alphas is not None and (
        not args.alphas or any(value <= 0 for value in args.alphas)
    ):
        parser.error("--alphas requires one or more values > 0")

    cfg = load_config(args.config)
    metric_key = selection_metric_key(cfg.evaluation.top_k)
    raw_master = load_master_df(cfg.export_dir)
    items = load_items_df(cfg.export_dir)
    if raw_master.empty:
        raise SystemExit(f"interactions.csv missing or empty: {cfg.export_dir}")
    master = select_model_view(
        cfg.export_dir,
        raw_master,
        complete_only=cfg.interactions.complete_only,
        view="all",
    )
    cutoffs = [date.fromisoformat(value) for value in args.cutoffs]
    air_dates = _air_dates(items)
    negative_scales = (
        args.negative_scales
        if args.negative_scales is not None
        else (cfg.als_model.negative_scales if args.view == "all" else [0.0])
    )
    half_lives = (
        args.half_lives
        if args.half_lives is not None
        else [cfg.als_model.recency_half_life_days]
    )
    factors_values = args.factors or [cfg.als_model.factors]
    regularization_values = args.regularizations or [cfg.als_model.regularization]
    alpha_values = args.alphas or [cfg.als_model.alpha]

    report: dict[str, Any] = {
        "generated_at": _utcnow(),
        "status": "running",
        "protocol": {
            "kind": "rolling_origin_quarterly",
            "view": args.view,
            "complete_only": cfg.interactions.complete_only,
            "cutoffs": [value.isoformat() for value in cutoffs],
            "selection_metric": "mean_validation_ndcg@10",
            "test_data_used": False,
            "negative_scales": negative_scales,
            "recency_half_lives_days": half_lives,
            "factors": factors_values,
            "regularizations": regularization_values,
            "alphas": alpha_values,
        },
        "variants": {},
    }
    output_dir = cfg.als_dir if args.view == "all" else cfg.als_dir / args.view
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / args.report_name
    scores: list[tuple[float, dict[str, float | int]]] = []
    search_space = itertools.product(
        factors_values,
        regularization_values,
        alpha_values,
        negative_scales,
        half_lives,
    )
    for factors, regularization, alpha, negative_scale, half_life in search_space:
        variant_config = cfg.als_model.model_copy(update={
            "factors": factors,
            "regularization": regularization,
            "alpha": alpha,
        })
        label = (
            f"f{factors}_r{regularization:g}_a{alpha:g}_"
            f"negative_scale_{negative_scale:g}_half_life_{half_life:g}d"
        )
        fold_reports: list[dict[str, Any]] = []
        fold_scores: list[float] = []
        for cutoff in cutoffs:
            train, validation, view_stats = build_fold(
                master, air_dates, cutoff, cfg, args.view
            )
            if train.empty or validation.empty:
                fold_reports.append({
                    "cutoff": cutoff.isoformat(),
                    "status": "insufficient_data",
                    "train_rows": len(train),
                    "validation_rows": len(validation),
                    **view_stats,
                })
                continue
            maps = IdMaps.from_interactions(
                pd.concat([train, validation], ignore_index=True)
            )
            model, confidence, elapsed = _train_variant(
                train,
                maps,
                variant_config,
                negative_scale,
                cfg.evaluation.random_seed,
                half_life,
                cutoff,
            )
            validation_end = splits.split_windows(cutoff)[
                "validation_end"
            ].date()
            catalogs = candidate_catalogs(items, train, maps, validation_end)
            primary = evaluate_group(
                _positive(validation),
                catalogs["interaction"],
                train,
                model,
                maps,
                cfg.evaluation.top_k,
            )
            score = primary.get("models", {}).get(
                "implicit_als", {}
            ).get(metric_key)
            if score is not None:
                fold_scores.append(float(score))
            fold_reports.append({
                "cutoff": cutoff.isoformat(),
                "validation_end": validation_end.isoformat(),
                "status": primary["status"],
                "train_rows": len(train),
                "validation_rows": len(validation),
                "matrix_nnz": int(confidence.nnz),
                "training_seconds": round(elapsed, 3),
                "validation_all": primary,
                **view_stats,
            })
            print(
                f"[als-cv] {label} cutoff={cutoff} train={len(train)} "
                f"validation={len(validation)} {metric_key}={score}",
                flush=True,
            )
        mean_score = float(np.mean(fold_scores)) if fold_scores else 0.0
        std_score = float(np.std(fold_scores)) if fold_scores else 0.0
        parameters: dict[str, float | int] = {
            "factors": factors,
            "regularization": regularization,
            "alpha": alpha,
            "negative_scale": negative_scale,
            "recency_half_life_days": half_life,
        }
        scores.append((mean_score, parameters))
        report["variants"][label] = {
            **parameters,
            "valid_folds": len(fold_scores),
            "mean_validation_ndcg@10": mean_score,
            "std_validation_ndcg@10": std_score,
            "folds": fold_reports,
        }
        report_path.write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
        )

    selected_score, selected_parameters = max(scores, key=lambda value: value[0])
    report["selection"] = {
        **selected_parameters,
        "mean_validation_ndcg@10": selected_score,
    }
    report["status"] = "complete"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[als-cv] report written to {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
