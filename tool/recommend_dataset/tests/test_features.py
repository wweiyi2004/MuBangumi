"""Feature building: strict mode, token namespaces, Chinese n-grams, sparsity."""
from __future__ import annotations

import numpy as np
import pandas as pd
import pytest
from scipy import sparse

from baseline.features import build_feature_matrix, episode_count_bucket
from src.config import ContentModelConfig


def _items_df() -> pd.DataFrame:
    return pd.DataFrame([
        {
            "subject_id": 1,
            "tags": ["治愈", "恋爱"], "meta_tags": ["TV"],
            "production": ["京都动画"], "director": ["山田尚子"],
            "series_composer": [], "original_work": ["文库"], "music": [],
            "voice_actors": ["早见沙织"], "platform": "TV",
            "year": 2026, "season": 1, "episode_count": 12,
            "summary": "这是一个治愈系恋爱故事的简介。",
            "related_prequel_sequel": [{"relation": "续作", "id": 2}],
            "score": 9.5, "rank": 10, "collection_total": 50000,
        },
        {
            "subject_id": 2,
            "tags": ["战斗"], "meta_tags": [],
            "production": ["BONES"], "director": [], "series_composer": [],
            "original_work": [], "music": [], "voice_actors": [],
            "platform": "WEB", "year": 2025, "season": 4, "episode_count": 26,
            "summary": "",
            "related_prequel_sequel": [],
            "score": 7.0, "rank": 200, "collection_total": 1000,
        },
    ])


def test_strict_mode_excludes_dynamic_features():
    items = _items_df()
    result = build_feature_matrix(items, ContentModelConfig(), strict=True)
    names = set(result["feature_names"])
    assert not any(name.startswith("dyn:") for name in names)
    assert "dyn:score:9-10" not in names
    assert "dyn:rank:top100" not in names


def test_opt_in_dynamic_features_appear():
    items = _items_df()
    result = build_feature_matrix(items, ContentModelConfig(), strict=False)
    names = set(result["feature_names"])
    assert "dyn:score:9-10" in names
    assert "dyn:rank:top100" in names
    assert "dyn:collection:10k+" in names


def test_token_namespaces():
    items = _items_df()
    names = set(build_feature_matrix(items, ContentModelConfig(), strict=True)["feature_names"])
    assert "tag:治愈" in names
    assert "tag:TV" in names                       # meta_tags uses the same namespace
    assert "staff:京都动画" in names               # production
    assert "staff:山田尚子" in names               # director shares the staff namespace
    assert "staff:文库" in names                   # original_work
    assert "actor:早见沙织" in names
    assert "ctx:platform:TV" in names
    assert "ctx:eps:1-12" in names
    assert "ctx:season:winter" in names
    assert "rel:续作:2" in names


def test_chinese_char_ngrams_produce_features():
    items = _items_df()
    cfg = ContentModelConfig(summary_min_df=1)  # one summary doc in this fixture
    result = build_feature_matrix(items, cfg, strict=True)
    names = list(result["feature_names"])
    # The summary is Chinese; character n-grams (not whitespace tokens) must exist.
    assert result["meta"]["summary_vocab_size"] > 0
    assert any(("治愈" in name or "恋爱" in name or "这是" in name) for name in names)


def test_summary_min_df_filters_rare_grams():
    items = _items_df()
    cfg = ContentModelConfig(summary_min_df=5)  # nothing appears 5+ times
    result = build_feature_matrix(items, cfg, strict=True)
    assert result["meta"]["summary_vocab_size"] == 0
    # No crash, no summary block.


def test_empty_fields_do_not_crash():
    items = pd.DataFrame([
        {
            "subject_id": 1, "tags": None, "meta_tags": None, "production": None,
            "director": None, "series_composer": None, "original_work": None,
            "music": None, "voice_actors": None, "platform": None, "year": None,
            "season": None, "episode_count": None, "summary": "",
            "related_prequel_sequel": None, "score": None, "rank": None,
            "collection_total": None,
        },
        {
            "subject_id": 2, "tags": ["治愈"], "meta_tags": [],
            "production": [], "director": [], "series_composer": [],
            "original_work": [], "music": [], "voice_actors": [],
            "platform": "TV", "year": 2026, "season": 2, "episode_count": 12,
            "summary": "有内容的简介。", "related_prequel_sequel": [],
            "score": None, "rank": None, "collection_total": None,
        },
    ])
    result = build_feature_matrix(items, ContentModelConfig(), strict=True)
    assert result["matrix"].shape[0] == 2
    assert "tag:治愈" in set(result["feature_names"])


def test_all_empty_raises():
    items = pd.DataFrame([
        {"subject_id": 1, "summary": "", "tags": [], "meta_tags": [],
         "production": [], "director": [], "series_composer": [],
         "original_work": [], "music": [], "voice_actors": [],
         "platform": None, "year": None, "season": None, "episode_count": None,
         "related_prequel_sequel": []},
    ])
    with pytest.raises(ValueError):
        build_feature_matrix(items, ContentModelConfig(), strict=True)


def test_matrix_stays_sparse():
    items = _items_df()
    result = build_feature_matrix(items, ContentModelConfig(), strict=True)
    matrix = result["matrix"]
    assert sparse.issparse(matrix)
    assert matrix.getformat() == "csr"
    assert matrix.shape == (2, len(result["feature_names"]))
    # Sparse by construction: far fewer stored entries than a dense grid.
    assert matrix.nnz < matrix.shape[0] * matrix.shape[1]
    # L2-normalized rows.
    norms = np.asarray((matrix.multiply(matrix)).sum(axis=1)).ravel()
    assert all(abs(n - 1.0) < 1e-6 for n in norms)


def test_episode_count_buckets():
    assert episode_count_bucket(1) == "1-12"
    assert episode_count_bucket(12) == "1-12"
    assert episode_count_bucket(13) == "13-24"
    assert episode_count_bucket(24) == "13-24"
    assert episode_count_bucket(25) == "25+"
    assert episode_count_bucket(0) is None
    assert episode_count_bucket(None) is None
    assert episode_count_bucket("junk") is None
