#!/usr/bin/env python3
"""Compare two persisted ALS models on an identical common test cohort."""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from baseline import metrics as mt
from baseline.als_model import IdMaps, rank_user
from run_als_baseline import (
    _owned_by_user,
    _positive,
    _positive_users,
    candidate_catalogs,
    select_model_view,
)
from run_content_baseline import load_items_df, load_master_df
from src.config import load_config
from src.splits import split_windows


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _load_model(directory: Path):
    import numpy as np
    from implicit.cpu.als import AlternatingLeastSquares
    from threadpoolctl import threadpool_limits

    user_ids = np.load(directory / "user_ids.npy").astype(str)
    subject_ids = np.load(directory / "subject_ids.npy").astype("int64")
    maps = IdMaps(
        user_ids=user_ids,
        subject_ids=subject_ids,
        user_index={value: index for index, value in enumerate(user_ids)},
        item_index={int(value): index for index, value in enumerate(subject_ids)},
    )
    with threadpool_limits(limits=1, user_api="blas"):
        model = AlternatingLeastSquares.load(directory / "model.npz")
    return model, maps


def _relevant_by_user(frame: pd.DataFrame, candidates: set[int]) -> dict[str, set[int]]:
    result: dict[str, set[int]] = {}
    for row in _positive(frame).itertuples(index=False):
        subject_id = int(row.subject_id)
        if subject_id in candidates:
            result.setdefault(str(row.anon_user_id), set()).add(subject_id)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Common-cohort ALS comparison")
    parser.add_argument("--baseline-config", required=True)
    parser.add_argument("--candidate-config", required=True)
    args = parser.parse_args()

    baseline_cfg = load_config(args.baseline_config)
    candidate_cfg = load_config(args.candidate_config)
    baseline_master = select_model_view(
        baseline_cfg.export_dir,
        load_master_df(baseline_cfg.export_dir),
        complete_only=baseline_cfg.interactions.complete_only,
        view="all",
        max_train_interactions_per_user=(
            baseline_cfg.interactions.max_train_interactions_per_user
        ),
    )
    candidate_master = select_model_view(
        candidate_cfg.export_dir,
        load_master_df(candidate_cfg.export_dir),
        complete_only=candidate_cfg.interactions.complete_only,
        view="all",
        max_train_interactions_per_user=(
            candidate_cfg.interactions.max_train_interactions_per_user
        ),
    )
    baseline_model, baseline_maps = _load_model(baseline_cfg.als_dir)
    candidate_model, candidate_maps = _load_model(candidate_cfg.als_dir)

    baseline_history = baseline_master[
        baseline_master["split"].isin(("train", "validation"))
    ]
    candidate_history = candidate_master[
        candidate_master["split"].isin(("train", "validation"))
    ]
    test_end = split_windows(candidate_cfg.splits.train_end_date)["test_end"].date()
    baseline_catalog = set(candidate_catalogs(
        load_items_df(baseline_cfg.export_dir),
        baseline_history,
        baseline_maps,
        test_end,
    )["interaction"])
    candidate_catalog = set(candidate_catalogs(
        load_items_df(candidate_cfg.export_dir),
        candidate_history,
        candidate_maps,
        test_end,
    )["interaction"])
    common_candidates = baseline_catalog & candidate_catalog

    baseline_relevant = _relevant_by_user(
        baseline_master[baseline_master["split"] == "test"], common_candidates
    )
    candidate_relevant = _relevant_by_user(
        candidate_master[candidate_master["split"] == "test"], common_candidates
    )
    baseline_profiles = _positive_users(baseline_history)
    candidate_profiles = _positive_users(candidate_history)
    baseline_owned = _owned_by_user(baseline_history)
    candidate_owned = _owned_by_user(candidate_history)

    common_relevant: dict[str, set[int]] = {}
    for user_id in sorted(set(baseline_relevant) & set(candidate_relevant)):
        if (
            user_id not in baseline_profiles
            or user_id not in candidate_profiles
            or user_id not in baseline_maps.user_index
            or user_id not in candidate_maps.user_index
        ):
            continue
        excluded = baseline_owned.get(user_id, set()) | candidate_owned.get(user_id, set())
        relevant = (
            baseline_relevant[user_id]
            & candidate_relevant[user_id]
        ) - excluded
        if relevant:
            common_relevant[user_id] = relevant

    top_k = sorted(candidate_cfg.evaluation.top_k)
    max_k = max(top_k)
    baseline_rows = []
    candidate_rows = []
    baseline_ranked_lists = []
    candidate_ranked_lists = []
    for user_id, relevant in common_relevant.items():
        excluded = baseline_owned.get(user_id, set()) | candidate_owned.get(user_id, set())
        baseline_ranked = rank_user(
            baseline_model, baseline_maps, user_id, common_candidates, excluded, max_k
        )
        candidate_ranked = rank_user(
            candidate_model, candidate_maps, user_id, common_candidates, excluded, max_k
        )
        baseline_rows.append(mt.per_user_metrics(baseline_ranked, relevant, top_k))
        candidate_rows.append(mt.per_user_metrics(candidate_ranked, relevant, top_k))
        baseline_ranked_lists.append(baseline_ranked)
        candidate_ranked_lists.append(candidate_ranked)

    report = {
        "generated_at": _utcnow(),
        "protocol": {
            "same_users": True,
            "same_relevant_items": True,
            "same_candidate_catalog": True,
            "history_exclusion": "union_of_both_model_histories",
        },
        "users": len(common_relevant),
        "relevant_interactions": sum(len(value) for value in common_relevant.values()),
        "candidate_items": len(common_candidates),
        "baseline": {
            **mt.mean_metrics(baseline_rows, top_k),
            "catalog_coverage": mt.catalog_coverage_at_k(
                baseline_ranked_lists, len(common_candidates), max_k
            ),
        },
        "candidate": {
            **mt.mean_metrics(candidate_rows, top_k),
            "catalog_coverage": mt.catalog_coverage_at_k(
                candidate_ranked_lists, len(common_candidates), max_k
            ),
        },
    }
    output = candidate_cfg.als_dir / "common_test_comparison.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    print(f"[compare] report written to {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
