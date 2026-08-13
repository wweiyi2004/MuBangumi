#!/usr/bin/env python3
"""Run the TF-IDF content recommendation baseline and offline evaluation.

Reads the exported dataset (subjects.csv, item_features.jsonl, interactions.csv
and the split files), builds a sparse TF-IDF content model, builds user
profiles from train interactions only, and evaluates against validation/test
ground truth. A popularity baseline (train interaction counts only) is included
for comparison. No network access. Insufficient data produces an explicit
insufficient_data report instead of fabricated scores.

Usage:
  python tool/recommend_dataset/run_content_baseline.py --config dataset_config.json
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))

from baseline import evaluate as ev  # noqa: E402
from baseline import metrics as mt  # noqa: E402
from baseline.content_model import ContentModel  # noqa: E402
from baseline.features import DYNAMIC_COLUMNS  # noqa: E402
from src import splits  # noqa: E402
from src.config import load_config  # noqa: E402
from src.model_views import cap_train_history  # noqa: E402

# Evaluation group templates: (name, split window, relevant subset filter).
# "all" -> every positive interaction in the window; "cold_item" /
# "strict_cold_new_release" -> restrict the ground truth to those item classes.
GROUP_SPECS = [
    ("validation_all", "validation", None),
    ("validation_cold_item", "validation", "cold_item"),
    ("validation_strict_cold_new_release", "validation", "strict_cold_new_release"),
    ("test_all", "test", None),
    ("test_cold_item", "test", "cold_item"),
    ("test_strict_cold_new_release", "test", "strict_cold_new_release"),
]

GROUP_NAME_TO_SPLIT = {name: split for name, split, _ in GROUP_SPECS}


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def load_items_df(export_dir: Path) -> pd.DataFrame:
    """item_features.jsonl -> DataFrame with parsed list/dict columns.

    Lines are read via the file iterator (newline = LF only). Using
    str.splitlines() would also split on U+2028/U+2029, which can legitimately
    appear inside summaries and would corrupt the record boundaries.
    """
    path = export_dir / "item_features.jsonl"
    if not path.exists():
        return pd.DataFrame()
    rows = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if stripped:
                rows.append(json.loads(stripped))
    if not rows:
        return pd.DataFrame()
    return pd.DataFrame(rows)


def load_master_df(export_dir: Path) -> pd.DataFrame:
    path = export_dir / "interactions.csv"
    if not path.exists():
        return pd.DataFrame()
    df = pd.read_csv(path, encoding="utf-8")
    df["subject_id"] = df["subject_id"].astype(int)
    return df


def subject_id_set(*frames: pd.DataFrame) -> set[int]:
    return {
        int(subject_id)
        for frame in frames
        for subject_id in frame["subject_id"]
    }


def popularity_ranking(candidates: list[int], train_df: pd.DataFrame) -> list[int]:
    """Rank candidates by train-period interaction counts (ties by subject_id)."""
    positive = train_df[~train_df["is_negative"].astype(bool)]
    counts = positive.groupby("subject_id").size().to_dict()
    return sorted(candidates, key=lambda sid: (-counts.get(int(sid), 0), int(sid)))


def evaluate_group(
    group_name: str,
    relevant_df: pd.DataFrame,
    candidate_ids: list[int],
    profiles: dict[str, np.ndarray],
    model,
    top_k: list[int],
    train_df: pd.DataFrame,
) -> dict:
    """Evaluate tfidf_content + popularity_baseline on one group."""
    raw_positives = int(len(relevant_df))
    raw_users = int(relevant_df["anon_user_id"].nunique()) if raw_positives else 0
    candidate_set = set(candidate_ids)
    owned_by_user: dict[str, set[int]] = {}
    for row in train_df.itertuples(index=False):
        owned_by_user.setdefault(str(row.anon_user_id), set()).add(int(row.subject_id))
    relevant_by_user: dict[str, set[int]] = {}
    for row in relevant_df.itertuples(index=False):
        user_id = str(row.anon_user_id)
        subject_id = int(row.subject_id)
        if (
            user_id in profiles
            and subject_id in candidate_set
            and subject_id not in owned_by_user.get(user_id, set())
        ):
            relevant_by_user.setdefault(user_id, set()).add(subject_id)
    user_ids = sorted(relevant_by_user)
    if not user_ids or raw_positives == 0:
        return {
            "status": "insufficient_data",
            "raw_users": raw_users,
            "raw_positives": raw_positives,
            "users": 0,
            "eligible_positives": 0,
            "candidate_items": len(candidate_ids),
            "models": {},
        }

    pop_ranked = popularity_ranking(candidate_ids, train_df)
    max_k = max(top_k)
    candidate_matrix, candidate_array = model.submatrix(candidate_ids)

    tfidf_rows: list[dict] = []
    pop_rows: list[dict] = []
    tfidf_ranked_lists: list[list[int]] = []
    pop_ranked_lists: list[list[int]] = []
    candidate_counts: list[int] = []
    for uid in user_ids:
        user_vec = profiles[uid]
        relevant = relevant_by_user[uid]
        excluded = owned_by_user.get(uid, set())
        tfidf_ranked = ev.score_matrix_and_rank(
            user_vec, candidate_matrix, candidate_array, excluded, max_k
        )
        pop_cut = [sid for sid in pop_ranked if sid not in excluded][:max_k]
        tfidf_rows.append(mt.per_user_metrics(tfidf_ranked, relevant, top_k))
        pop_rows.append(mt.per_user_metrics(pop_cut, relevant, top_k))
        tfidf_ranked_lists.append(tfidf_ranked)
        pop_ranked_lists.append(pop_cut)
        candidate_counts.append(len(candidate_set - excluded))

    return {
        "status": "ok",
        "raw_users": raw_users,
        "raw_positives": raw_positives,
        "users": len(user_ids),
        "eligible_positives": sum(len(value) for value in relevant_by_user.values()),
        "candidate_items": len(candidate_ids),
        "mean_candidates_per_user": round(float(np.mean(candidate_counts)), 2),
        "models": {
            "tfidf_content": {
                **mt.mean_metrics(tfidf_rows, top_k),
                "catalog_coverage": mt.catalog_coverage_at_k(
                    tfidf_ranked_lists, len(candidate_ids), max_k
                ),
            },
            "popularity_baseline": {
                **mt.mean_metrics(pop_rows, top_k),
                "catalog_coverage": mt.catalog_coverage_at_k(
                    pop_ranked_lists, len(candidate_ids), max_k
                ),
            },
        },
    }


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Run the TF-IDF content baseline")
    parser.add_argument("--config", default="dataset_config.json", help="JSON config file")
    args = parser.parse_args()

    cfg = load_config(args.config)
    export_dir = cfg.export_dir
    baseline_dir = cfg.baseline_dir
    top_k = sorted(cfg.evaluation.top_k)
    strict = cfg.evaluation.strict_temporal
    negative_lambda = cfg.evaluation.negative_profile_weight
    seed = cfg.evaluation.random_seed
    np.random.seed(seed)

    items = load_items_df(export_dir)
    master = load_master_df(export_dir)
    raw_master_interactions = int(len(master))
    if cfg.interactions.complete_only and not master.empty:
        if "collection_complete" not in master.columns:
            raise SystemExit(
                "complete_only requires collection_complete in interactions.csv; "
                "rerun export_dataset.py"
            )
        master = master[master["collection_complete"].astype(bool)].copy()
    completeness_eligible_interactions = int(len(master))
    master = cap_train_history(
        master,
        cfg.interactions.max_train_interactions_per_user,
    )
    model_view_interactions = int(len(master))

    report: dict = {
        "generated_at": _utcnow(),
        "config": {
            "train_end_date": cfg.splits.train_end_date.isoformat(),
            "strict_temporal": strict,
            "allow_dynamic_popularity_features": cfg.evaluation.allow_dynamic_popularity_features,
            "potential_feature_leakage": (
                not strict or cfg.evaluation.allow_dynamic_popularity_features
            ),
            "negative_profile_weight": negative_lambda,
            "top_k": top_k,
            "random_seed": seed,
            "complete_only": cfg.interactions.complete_only,
            "max_train_interactions_per_user": (
                cfg.interactions.max_train_interactions_per_user
            ),
        },
        "data_summary": {},
        "groups": {},
    }

    def finish_insufficient(reason: str) -> int:
        report["data_summary"] = {
            "subjects": int(len(items)) if not items.empty else 0,
            "status": "insufficient_data",
            "reason": reason,
        }
        for name, _, _ in GROUP_SPECS:
            report["groups"][name] = {"status": "insufficient_data", "models": {}}
        _write_report(report, baseline_dir)
        print(f"[baseline] insufficient data: {reason}")
        return 0

    if items.empty:
        return finish_insufficient("item_features.jsonl missing or empty")
    if master.empty:
        return finish_insufficient("interactions.csv missing or empty")

    content_item_ids = set(int(subject_id) for subject_id in items["subject_id"])
    master = master[master["subject_id"].astype(int).isin(content_item_ids)].copy()

    train_df = master[master["split"] == "train"]
    validation_df = master[
        (master["split"] == "validation") & (~master["is_negative"].astype(bool))
    ]
    test_df = master[
        (master["split"] == "test") & (~master["is_negative"].astype(bool))
    ]
    # The content model itself only needs item features - build and persist it
    # even when the evaluation windows are empty (insufficient data).
    model = ContentModel.fit(items, cfg.content_model, strict=strict)
    model.save(baseline_dir)

    if train_df.empty or validation_df.empty or test_df.empty:
        return finish_insufficient("one of the temporal split windows is empty")

    # ------------------------------------------------------------- item classes
    air_dates = {
        int(row["subject_id"]): row.get("air_date") for _, row in items.iterrows()
    }
    train_positive_counts: dict[int, int] = {}
    for _, row in train_df[~train_df["is_negative"].astype(bool)].iterrows():
        sid = int(row["subject_id"])
        train_positive_counts[sid] = train_positive_counts.get(sid, 0) + 1
    val_test_positive_ids = subject_id_set(validation_df, test_df)
    item_flags = splits.compute_item_flags(
        air_dates, train_positive_counts, val_test_positive_ids, cfg.splits.train_end_date
    )
    cold_ids = {sid for sid, flags in item_flags.items() if "cold_item" in flags}
    strict_cold_ids = {
        sid for sid, flags in item_flags.items() if "strict_cold_new_release" in flags
    }

    # -------------------------------------------------------------- candidates
    windows = splits.split_windows(cfg.splits.train_end_date)
    # Candidate availability is global, but ownership exclusion is per-user in
    # evaluate_group.  A global exclusion here would collapse the catalog to
    # cold items and make the popularity baseline meaningless.
    candidates = {
        "validation": ev.candidate_subject_ids(
            items, windows["validation_end"].date(), set(), model
        ),
        "test": ev.candidate_subject_ids(
            items, windows["test_end"].date(), set(), model
        ),
    }

    # --------------------------------------------------------------- profiles
    profiles = ev.build_user_profiles(train_df, model, negative_lambda)
    # test_incremental: profiles allowed to additionally use validation positives.
    incremental_train = pd.concat([
        train_df,
        master[(master["split"] == "validation") & (~master["is_negative"].astype(bool))],
    ])
    profiles_incremental = ev.build_user_profiles(incremental_train, model, negative_lambda)

    report["data_summary"] = {
        "subjects": int(len(items)),
        "n_features": int(model.matrix.shape[1]),
        "raw_master_interactions": raw_master_interactions,
        "completeness_eligible_interactions": completeness_eligible_interactions,
        "model_view_interactions": model_view_interactions,
        "content_eligible_interactions": int(len(master)),
        "excluded_missing_content_interactions": raw_master_interactions - int(len(master)),
        "users_with_train_positive": int(len(profiles)),
        "train_positive_interactions": int(
            len(train_df) - int(train_df["is_negative"].astype(bool).sum())
        ),
        "validation_positive_interactions": int(len(validation_df)),
        "test_positive_interactions": int(len(test_df)),
        "candidate_items_validation": len(candidates["validation"]),
        "candidate_items_test": len(candidates["test"]),
        "cold_items": len(cold_ids),
        "strict_cold_new_release_items": len(strict_cold_ids),
    }

    # ---------------------------------------------------------------- evaluate
    for group_name, split_name, subset in GROUP_SPECS:
        relevant_df = validation_df if split_name == "validation" else test_df
        if subset == "cold_item":
            relevant_df = relevant_df[
                relevant_df["subject_id"].astype(int).isin(cold_ids)
            ]
        elif subset == "strict_cold_new_release":
            relevant_df = relevant_df[
                relevant_df["subject_id"].astype(int).isin(strict_cold_ids)
            ]
        group_candidates = candidates[split_name]
        report["groups"][group_name] = evaluate_group(
            group_name, relevant_df, group_candidates, profiles, model,
            top_k, train_df,
        )

    # test_incremental uses train+validation profiles (never test).
    report["groups"]["test_incremental"] = evaluate_group(
        "test_incremental", test_df, candidates["test"], profiles_incremental,
        model, top_k, incremental_train,
    )

    _write_report(report, baseline_dir)
    _print_summary(report, baseline_dir)
    return 0


def _write_report(report: dict, baseline_dir: Path) -> None:
    baseline_dir.mkdir(parents=True, exist_ok=True)
    (baseline_dir / "baseline_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def _print_summary(report: dict, baseline_dir: Path) -> None:
    print(f"[baseline] subjects={report['data_summary'].get('subjects')} "
          f"users={report['data_summary'].get('users_with_train_positive')} "
          f"features={report['data_summary'].get('n_features')}")
    for name, group in report["groups"].items():
        status = group["status"]
        if status == "ok":
            tfidf = group["models"]["tfidf_content"]
            pop = group["models"]["popularity_baseline"]
            print(f"[baseline] {name:<38} status=ok users={group['users']} "
                  f"positives={group['eligible_positives']} "
                  f"recall@10 tfidf={tfidf.get('recall@10')} pop={pop.get('recall@10')} "
                  f"ndcg@10 tfidf={tfidf.get('ndcg@10')} "
                  f"mrr@20 tfidf={tfidf.get('mrr@20')}")
        else:
            print(f"[baseline] {name:<38} status={status} users={group['users']} "
                  f"positives={group['raw_positives']} candidates={group['candidate_items']}")
    print(f"[baseline] report written to {baseline_dir / 'baseline_report.json'}")


if __name__ == "__main__":
    sys.exit(main())
