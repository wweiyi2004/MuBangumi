"""check_dataset.py exit codes: 0 = ready, 2 = valid but insufficient, 1 = broken."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_TOOL_DIR = Path(__file__).resolve().parents[1]


def _write_config(tmp_path: Path) -> Path:
    config = {
        "output": {"data_dir": "data"},
        "splits": {"train_end_date": "2025-12-31"},
        "evaluation": {"strict_temporal": True},
    }
    config_path = tmp_path / "dataset_config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    return config_path


def _write_report(tmp_path: Path, **overrides) -> Path:
    report = {
        "subjects": {"total": 1000, "with_air_date": 1000},
        "interactions": {
            "subject_reference_coverage": 1.0,
            "users": 600,
            "missing_distinct_subjects": 0,
        },
        "splits": {
            "train": {"users": 600, "items": 5000, "interactions": 60000},
            "validation": {"users": 100, "items": 200, "interactions": 1000},
            "test": {"users": 80, "items": 150, "interactions": 800},
        },
        "temporal_quality": {
            "updated_at_coverage": 1.0,
            "unassigned_interactions": 0,
            "future_interactions": 0,
            "invalid_temporal_interactions": 0,
            "train_interactions_after_cutoff": 0,
        },
        "readiness": {
            "cold_validation_items": 150,
            "cold_test_items": 120,
            "als_blockers": [],
        },
        "item_classes": {"strict_cold_new_release": 100},
    }
    report.update(overrides)
    export_dir = tmp_path / "data" / "export"
    export_dir.mkdir(parents=True, exist_ok=True)
    (export_dir / "dataset_report.json").write_text(
        json.dumps(report, ensure_ascii=False), encoding="utf-8"
    )
    config = _write_config(tmp_path)
    return config


def _run(config_path: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(REPO_TOOL_DIR / "check_dataset.py"),
         "--config", str(config_path)],
        capture_output=True, text=True, timeout=120,
    )


def _run_hybrid(config_path: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(REPO_TOOL_DIR / "check_dataset.py"),
         "--config", str(config_path), "--require-hybrid"],
        capture_output=True, text=True, timeout=120,
    )


def test_qualified_dataset_exit_0(tmp_path):
    config = _write_report(tmp_path)
    result = _run(config)
    assert result.returncode == 0, result.stderr
    assert "ALL CHECKS PASSED" in result.stdout


def test_small_dataset_exit_2(tmp_path):
    """Structure valid but thresholds not met (the current dry-run situation)."""
    config = _write_report(
        tmp_path,
        interactions={
            "subject_reference_coverage": 0.0027,
            "users": 6,
            "missing_distinct_subjects": 2601,
        },
        splits={
            "train": {"users": 2, "items": 2, "interactions": 2},
            "validation": {"users": 1, "items": 8, "interactions": 8},
            "test": {"users": 0, "items": 0, "interactions": 0},
        },
        readiness={"cold_validation_items": 8, "cold_test_items": 0, "als_blockers": []},
    )
    result = _run(config)
    assert result.returncode == 2
    assert "not ready for ALS" in result.stderr


def test_low_metadata_coverage_does_not_block_pure_als(tmp_path):
    config = _write_report(
        tmp_path,
        interactions={
            "subject_reference_coverage": 0.48,
            "users": 600,
            "missing_distinct_subjects": 10000,
        },
        readiness={
            "cold_validation_items": 500,
            "cold_test_items": 400,
            "content_cold_validation_items": 20,
            "content_cold_test_items": 30,
        },
    )
    als_result = _run(config)
    hybrid_result = _run_hybrid(config)
    assert als_result.returncode == 0, als_result.stderr
    assert "hybrid readiness: NOT READY" in als_result.stdout
    assert hybrid_result.returncode == 2
    assert "not ready for hybrid" in hybrid_result.stderr


def test_low_metadata_coverage_is_advisory_when_cold_samples_are_ready(tmp_path):
    config = _write_report(
        tmp_path,
        interactions={
            "subject_reference_coverage": 0.48,
            "users": 600,
            "missing_distinct_subjects": 10000,
        },
        readiness={
            "cold_validation_items": 500,
            "cold_test_items": 400,
            "content_cold_validation_items": 120,
            "content_cold_test_items": 130,
        },
    )
    result = _run_hybrid(config)
    assert result.returncode == 0, result.stderr
    assert "metadata coverage target" in result.stdout


def test_missing_report_exit_1(tmp_path):
    config = _write_config(tmp_path)
    result = _run(config)
    assert result.returncode == 1
    assert "dataset_report.json not found" in result.stderr


def test_corrupted_report_exit_1(tmp_path):
    config = _write_report(tmp_path)
    (tmp_path / "data" / "export" / "dataset_report.json").write_text(
        "{not json", encoding="utf-8"
    )
    result = _run(config)
    assert result.returncode == 1
    assert "corrupted" in result.stderr


def test_missing_key_exit_1(tmp_path):
    """A logically inconsistent report (missing required sections) is exit 1."""
    config = _write_report(tmp_path)
    report = json.loads((tmp_path / "data" / "export" / "dataset_report.json").read_text(
        encoding="utf-8"))
    del report["temporal_quality"]
    (tmp_path / "data" / "export" / "dataset_report.json").write_text(
        json.dumps(report), encoding="utf-8")
    result = _run(config)
    assert result.returncode == 1
    assert "missing required key" in result.stderr
