#!/usr/bin/env python3
"""Dataset quality gate for ALS training readiness.

Reads the exported dataset_report.json and prints a non-sensitive summary.

Exit codes:
  0  - all training-readiness checks pass
  2  - data structure is valid but the dataset does not meet the thresholds
       (expected for the current small dry-run dataset)
  1  - the report file is missing / corrupted / logically inconsistent

Usage:
  python tool/recommend_dataset/check_dataset.py --config dataset_config.json
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from src.config import load_config

# ALS only needs interaction scale and clean temporal splits. Content metadata
# coverage and cold-item sample sizes are a separate hybrid-model gate.
ALS_THRESHOLDS = {
    "valid_users_ge": 500,
    "positive_train_interactions_ge": 50000,
    "validation_interactions_gt": 0,
    "test_interactions_gt": 0,
    "temporal_leakage_rows_eq": 0,
}
HYBRID_THRESHOLDS = {
    "content_cold_validation_items_ge": 100,
    "content_cold_test_items_ge": 100,
}


def _fail(message: str) -> int:
    print(f"[check_dataset] ERROR: {message}", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Dataset readiness checks")
    parser.add_argument("--config", default="dataset_config.json", help="JSON config file")
    parser.add_argument(
        "--require-hybrid",
        action="store_true",
        help="also require content metadata coverage and cold-start evaluation sizes",
    )
    args = parser.parse_args()

    try:
        cfg = load_config(args.config)
    except Exception as exc:  # noqa: BLE001 - config errors are exit 1
        return _fail(f"cannot load config: {exc}")

    report_path = cfg.export_dir / "dataset_report.json"
    if not report_path.exists():
        return _fail(f"dataset_report.json not found at {report_path}; run export_dataset.py first")

    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except (ValueError, OSError) as exc:
        return _fail(f"dataset_report.json is corrupted: {exc}")

    # ---- collect all values needed for the checks -------------------------
    try:
        interactions = report["interactions"]
        splits_ = report["splits"]
        temporal = report["temporal_quality"]
        readiness = report.get("readiness", {})
        item_classes = report["item_classes"]
    except KeyError as exc:
        return _fail(f"dataset_report.json is missing required key {exc}; "
                     f"re-run export_dataset.py with the current tool version")

    subject_reference_coverage = float(interactions["subject_reference_coverage"])
    users = int(interactions.get(
        "train_positive_users",
        interactions.get("training_users", interactions["users"]),
    ))
    train_positives = int(splits_["train"]["interactions"])
    validation_positives = int(splits_["validation"]["interactions"])
    test_positives = int(splits_["test"]["interactions"])
    cold_validation_items = int(readiness.get("cold_validation_items", 0))
    cold_test_items = int(readiness.get("cold_test_items", 0))
    content_cold_validation_items = int(
        readiness.get("content_cold_validation_items", cold_validation_items)
    )
    content_cold_test_items = int(
        readiness.get("content_cold_test_items", cold_test_items)
    )
    temporal_leakage = int(temporal["train_interactions_after_cutoff"])
    missing_subjects = int(interactions.get("missing_distinct_subjects", 0))
    future_interactions = int(temporal.get("future_interactions", 0))
    invalid_temporal = int(temporal.get("invalid_temporal_interactions", 0))
    strict_cold = int(item_classes.get("strict_cold_new_release", 0))

    # ---- run the checks ----------------------------------------------------
    als_checks = [
        ("valid_users", users, ALS_THRESHOLDS["valid_users_ge"], "ge"),
        ("positive_train_interactions", train_positives,
         ALS_THRESHOLDS["positive_train_interactions_ge"], "ge"),
        ("validation_interactions", validation_positives,
         ALS_THRESHOLDS["validation_interactions_gt"], "gt"),
        ("test_interactions", test_positives, ALS_THRESHOLDS["test_interactions_gt"], "gt"),
        ("temporal_leakage_rows", temporal_leakage,
         ALS_THRESHOLDS["temporal_leakage_rows_eq"], "eq"),
    ]
    hybrid_checks = [
        ("content_cold_validation_items", content_cold_validation_items,
         HYBRID_THRESHOLDS["content_cold_validation_items_ge"], "ge"),
        ("content_cold_test_items", content_cold_test_items,
         HYBRID_THRESHOLDS["content_cold_test_items_ge"], "ge"),
    ]
    checks = als_checks + hybrid_checks if args.require_hybrid else als_checks

    print("[check_dataset] dataset quality summary")
    print(f"  subjects collected        : {report['subjects']['total']}")
    print(f"  subject reference coverage: {subject_reference_coverage} "
          f"(missing distinct: {missing_subjects})")
    print(f"  model-eligible users      : {users}")
    seed_users = report.get("seed_users", {})
    if seed_users:
        print(
            f"  collection complete users : "
            f"{seed_users.get('collection_complete', 0)} / "
            f"{seed_users.get('requested', 0)}"
        )
    core_train = (
        report.get("model_views", {})
        .get("variants", {})
        .get("core", {})
        .get("train", {})
        .get("interactions", 0)
    )
    print(f"  core train interactions   : {core_train}")
    print(f"  positive train            : {train_positives}")
    print(f"  validation positives      : {validation_positives}")
    print(f"  test positives            : {test_positives}")
    print(f"  cold validation items     : {cold_validation_items}")
    print(f"  cold test items           : {cold_test_items}")
    print(f"  content cold validation   : {content_cold_validation_items}")
    print(f"  content cold test         : {content_cold_test_items}")
    print(f"  strict_cold_new_release   : {strict_cold}")
    print(f"  temporal leakage rows     : {temporal_leakage}")
    print(f"  future interactions       : {future_interactions} "
          f"| invalid temporal: {invalid_temporal}")
    print(f"  updated_at coverage       : {temporal.get('updated_at_coverage')}")

    failed = []
    for name, value, threshold, op in checks:
        passed = {
            "ge": value >= threshold,
            "gt": value > threshold,
            "eq": value == threshold,
        }[op]
        mark = "PASS" if passed else "FAIL"
        print(f"  [{mark}] {name}: {value} (threshold {op} {threshold})")
        if not passed:
            failed.append(name)

    hybrid_ready = all({
        "ge": value >= threshold,
        "gt": value > threshold,
        "eq": value == threshold,
    }[op] for _, value, threshold, op in hybrid_checks)
    if not args.require_hybrid:
        print(f"  [INFO] hybrid readiness: {'PASS' if hybrid_ready else 'NOT READY'}")
    print(
        f"  [INFO] metadata coverage target: {subject_reference_coverage} / 0.98 "
        f"({'met' if subject_reference_coverage >= 0.98 else 'advisory only'})"
    )

    if not failed:
        target = "hybrid training" if args.require_hybrid else "ALS training"
        print(f"[check_dataset] ALL CHECKS PASSED - dataset is ready for {target}")
        return 0
    target = "hybrid training" if args.require_hybrid else "ALS training"
    print(f"[check_dataset] structure valid, but {len(failed)} threshold(s) not met "
          f"({', '.join(failed)}) - dataset not ready for {target}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
