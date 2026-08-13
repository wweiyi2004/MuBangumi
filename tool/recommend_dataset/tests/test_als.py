"""Implicit ALS matrix and ranking unit tests."""
from __future__ import annotations

from types import SimpleNamespace

import numpy as np
import pandas as pd
import pytest

from baseline.als_model import IdMaps, build_confidence_matrix, rank_user
from src.config import AlsModelConfig


def _frame() -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "anon_user_id": "u1",
                "subject_id": 10,
                "implicit_weight": 4.0,
                "negative_weight": 0.0,
                "is_negative": False,
                "updated_at": "2025-12-31T00:00:00Z",
            },
            {
                "anon_user_id": "u1",
                "subject_id": 20,
                "implicit_weight": 0.0,
                "negative_weight": 1.0,
                "is_negative": True,
                "updated_at": "2024-12-31T00:00:00Z",
            },
            {
                "anon_user_id": "u2",
                "subject_id": 30,
                "implicit_weight": 1.0,
                "negative_weight": 0.0,
                "is_negative": False,
                "updated_at": "2025-06-30T00:00:00Z",
            },
        ]
    )


def test_confidence_matrix_positive_only_and_signed_negative():
    frame = _frame()
    maps = IdMaps.from_interactions(frame)

    positive_only = build_confidence_matrix(frame, maps, negative_scale=0.0)
    signed = build_confidence_matrix(frame, maps, negative_scale=0.25)

    u1 = maps.user_index["u1"]
    assert positive_only[u1, maps.item_index[10]] == pytest.approx(4.0)
    assert positive_only[u1, maps.item_index[20]] == 0.0
    assert signed[u1, maps.item_index[20]] == pytest.approx(-0.25)


def test_confidence_matrix_applies_fold_local_recency_decay():
    frame = _frame()
    maps = IdMaps.from_interactions(frame)
    decayed = build_confidence_matrix(
        frame,
        maps,
        negative_scale=0.25,
        recency_half_life_days=365,
        reference_time="2025-12-31T00:00:00Z",
    )
    u1 = maps.user_index["u1"]
    assert decayed[u1, maps.item_index[10]] == pytest.approx(4.0)
    assert decayed[u1, maps.item_index[20]] == pytest.approx(-0.125, rel=1e-3)


def test_rank_user_excludes_only_supplied_history_and_breaks_ties():
    frame = _frame()
    maps = IdMaps.from_interactions(frame)
    model = SimpleNamespace(
        user_factors=np.asarray([[1.0, 0.0], [0.0, 1.0]]),
        item_factors=np.asarray([[1.0, 0.0], [0.0, 1.0], [0.0, 1.0]]),
    )

    ranked = rank_user(model, maps, "u1", [30, 20, 10], {10}, 3)
    assert ranked == [20, 30]


def test_als_config_rejects_invalid_ranges():
    with pytest.raises(ValueError):
        AlsModelConfig(factors=0)
    with pytest.raises(ValueError):
        AlsModelConfig(negative_scales=[])
    with pytest.raises(ValueError):
        AlsModelConfig(negative_scales=[-0.1])
    with pytest.raises(ValueError):
        AlsModelConfig(recency_half_life_days=-1)
