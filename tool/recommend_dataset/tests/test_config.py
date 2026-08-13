"""Config loading, defaults and validation."""
from __future__ import annotations

import json
from datetime import date

import pytest

from src.config import (
    ApiConfig,
    DatasetConfig,
    InteractionsConfig,
    SubjectsConfig,
    load_config,
)


def test_defaults():
    cfg = DatasetConfig()
    assert cfg.api.qps == 1.0
    assert cfg.api.max_concurrency == 2
    assert cfg.api.max_retries == 5
    assert cfg.splits.train_end_date == date(2026, 6, 30)
    assert cfg.subjects.use_calendar is True
    assert cfg.subjects.fetch_persons is False
    assert cfg.als_model.factors == 64
    assert cfg.als_model.negative_scales == [0.0, 0.25]


def test_invalid_api_qps():
    with pytest.raises(ValueError):
        ApiConfig(qps=0)


def test_invalid_concurrency():
    with pytest.raises(ValueError):
        ApiConfig(max_concurrency=0)


def test_invalid_base_url():
    with pytest.raises(ValueError):
        ApiConfig(base_url="ftp://example.com")


def test_invalid_collection_type():
    with pytest.raises(ValueError):
        InteractionsConfig(collection_types=["bogus"])


def test_invalid_quarter():
    with pytest.raises(ValueError):
        SubjectsConfig(year_quarters=[[2026, 5]])


def test_invalid_page_size():
    with pytest.raises(ValueError):
        InteractionsConfig(page_size=101)


def test_load_config_resolves_paths(tmp_path):
    (tmp_path / "dataset_config.json").write_text(
        json.dumps(
            {
                "api": {"qps": 2.0},
                "output": {"data_dir": "mydata"},
                "splits": {"train_end_date": "2024-01-15"},
            }
        ),
        encoding="utf-8",
    )
    cfg = load_config(tmp_path / "dataset_config.json")
    assert cfg.api.qps == 2.0
    assert cfg.data_dir == (tmp_path / "mydata").resolve()
    assert cfg.checkpoint_db == (tmp_path / "mydata" / "checkpoints.sqlite").resolve()
    assert cfg.export_dir == (tmp_path / "mydata" / "export").resolve()
    assert cfg.als_dir == (tmp_path / "mydata" / "als").resolve()
    assert cfg.salt_path == (tmp_path / "mydata" / "salt.txt").resolve()
    assert cfg.splits.train_end_date == date(2024, 1, 15)


def test_load_config_missing_file(tmp_path):
    with pytest.raises(FileNotFoundError):
        load_config(tmp_path / "nope.json")


def test_load_config_invalid_json(tmp_path):
    (tmp_path / "bad.json").write_text("{not json", encoding="utf-8")
    with pytest.raises(ValueError):
        load_config(tmp_path / "bad.json")


def test_load_config_unknown_keys_ignored(tmp_path):
    (tmp_path / "cfg.json").write_text(
        json.dumps({"api": {"qps": 1.0, "something_new": 1}, "junk": True}),
        encoding="utf-8",
    )
    cfg = load_config(tmp_path / "cfg.json")
    assert cfg.api.qps == 1.0
