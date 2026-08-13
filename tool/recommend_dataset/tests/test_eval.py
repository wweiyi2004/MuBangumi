"""Evaluation: metric math, profile discipline, candidate filtering."""
from __future__ import annotations

import datetime as dt

import numpy as np
import pandas as pd
import pytest
from scipy import sparse

from baseline import evaluate as ev
from baseline import metrics as mt
from baseline.content_model import ContentModel


def _make_model(subject_ids) -> ContentModel:
    """Hand-built model: one unique one-hot feature per item."""
    n = len(subject_ids)
    matrix = sparse.eye(n, format="csr")
    return ContentModel(matrix, np.asarray(subject_ids, dtype=int),
                        [f"f{i}" for i in range(n)], {"n_items": n})


def _row(user: str, sid: int, weight: float, negative: bool = False,
         neg_weight: float = 0.0) -> dict:
    return {
        "anon_user_id": user, "subject_id": sid, "implicit_weight": weight,
        "is_negative": negative, "negative_weight": neg_weight,
    }


# ------------------------------------------------------------------ metrics
def test_recall_ndcg_mrr_manual():
    ranked = [1, 2, 3, 4, 5]
    relevant = {2, 4}
    assert mt.precision_at_k(ranked, relevant, 5) == pytest.approx(0.4)
    assert mt.recall_at_k(ranked, relevant, 5) == pytest.approx(1.0)
    assert mt.f1_at_k(ranked, relevant, 5) == pytest.approx(4 / 7)
    assert mt.recall_at_k(ranked, relevant, 2) == pytest.approx(0.5)
    assert mt.recall_at_k(ranked, relevant, 1) == 0.0
    assert mt.hit_rate_at_k(ranked, relevant, 1) == 0.0
    assert mt.hit_rate_at_k(ranked, relevant, 2) == 1.0
    assert mt.mrr_at_k(ranked, relevant, 5) == pytest.approx(0.5)
    assert mt.mrr_at_k(ranked, relevant, 1) == 0.0
    expected_ndcg = (1 / np.log2(3) + 1 / np.log2(5)) / (1 + 1 / np.log2(3))
    assert mt.ndcg_at_k(ranked, relevant, 5) == pytest.approx(expected_ndcg)


def test_ndcg_binary_relevance_ideal():
    ranked = [1, 2, 3]
    relevant = {1, 2, 3}
    assert mt.ndcg_at_k(ranked, relevant, 3) == pytest.approx(1.0)


def test_per_user_and_mean_metrics():
    rows = [
        mt.per_user_metrics([1, 2], {2}, [5, 10, 20]),
        mt.per_user_metrics([1, 2], {9}, [5, 10, 20]),
    ]
    means = mt.mean_metrics(rows, [5, 10, 20])
    assert means["precision@5"] == pytest.approx(0.1)
    assert means["recall@5"] == pytest.approx(0.5)
    assert means["f1@5"] == pytest.approx(1 / 6, abs=1e-6)
    # ndcg: user1 hits at position 2 -> 1/log2(3); user2 no hit -> 0; mean halves it.
    assert means["ndcg@10"] == pytest.approx((1 / np.log2(3)) / 2)
    assert means["hit_rate@10"] == pytest.approx(0.5)
    assert means["mrr@20"] == pytest.approx(0.25)


def test_custom_top_k_produces_configured_ndcg_key_only():
    """With top_k=[5, 20] per-user metrics contain ndcg@20, not ndcg@10 -
    variant selection must not read a hardcoded 'ndcg@10'."""
    metrics = mt.per_user_metrics([1, 2], {2}, [5, 20])
    assert "ndcg@20" in metrics
    assert "ndcg@10" not in metrics
    assert metrics["ndcg@20"] == pytest.approx(1 / np.log2(3))


def test_selection_metric_key_keeps_ndcg10_with_default_top_k():
    from run_als_baseline import selection_metric_key

    assert selection_metric_key([5, 10, 20]) == "ndcg@10"


def test_selection_metric_key_uses_largest_k_when_10_missing():
    from run_als_baseline import selection_metric_key

    assert selection_metric_key([5, 20]) == "ndcg@20"
    assert selection_metric_key([]) == "ndcg@10"


def test_variant_selection_score_nonzero_with_custom_top_k():
    """top_k=[5, 20]: the configured metric key yields a real score instead
    of the hardcoded-ndcg@10 miss defaulting every variant to 0.0."""
    from types import SimpleNamespace

    from baseline.als_model import IdMaps
    from run_als_baseline import evaluate_group, selection_metric_key

    history = pd.DataFrame([
        {"anon_user_id": "u1", "subject_id": 11, "implicit_weight": 1.0,
         "negative_weight": 0.0, "is_negative": False},
    ])
    maps = IdMaps.from_interactions(pd.DataFrame([
        {"anon_user_id": "u1", "subject_id": 11},
        {"anon_user_id": "u1", "subject_id": 10},
    ]))
    relevant = pd.DataFrame([{"anon_user_id": "u1", "subject_id": 10}])
    # item_factors rows follow maps.item_index: subject 10 -> index 0.
    model = SimpleNamespace(
        user_factors=np.asarray([[1.0, 0.0]]),
        item_factors=np.asarray([[1.0, 0.0], [0.0, 1.0]]),
    )
    top_k = [5, 20]
    groups = evaluate_group(relevant, [10, 11], history, model, maps, top_k)
    key = selection_metric_key(top_k)
    assert key == "ndcg@20"
    implicit_als = groups["models"]["implicit_als"]
    assert "ndcg@10" not in implicit_als
    assert implicit_als[key] == pytest.approx(1.0)


def test_per_user_metrics_empty_top_k_falls_back_to_default():
    """An empty top_k must not crash with IndexError; fall back to the legacy
    default [10] so the ndcg@10 selection key keeps existing."""
    metrics = mt.per_user_metrics([1, 2], {2}, [])
    assert metrics["ndcg@10"] == pytest.approx(1 / np.log2(3))
    assert metrics["hit_rate@10"] == 1.0
    assert metrics["mrr@10"] == pytest.approx(0.5)


def test_catalog_coverage():
    ranked_lists = [[1, 2], [2, 3], [1]]
    assert mt.catalog_coverage_at_k(ranked_lists, total_candidates=5, k=2) == pytest.approx(3 / 5)
    assert mt.catalog_coverage_at_k([], total_candidates=5, k=2) == 0.0


# ------------------------------------------------------------- user profiles
def test_weighted_centroid_profile():
    model = _make_model([1, 2, 3])
    train_df = pd.DataFrame([
        _row("u1", 1, 4.0),
        _row("u1", 2, 1.0),
    ])
    profiles = ev.build_user_profiles(train_df, model, negative_profile_weight=0.0)
    raw = np.array([4.0, 1.0, 0.0])
    expected = raw / np.linalg.norm(raw)
    assert set(profiles) == {"u1"}
    assert np.allclose(profiles["u1"], expected)


def test_negative_profile_correction():
    model = _make_model([1, 2, 3])
    train_df = pd.DataFrame([
        _row("u2", 1, 3.0),
        _row("u2", 2, 1.0),
        _row("u2", 3, 0.0, negative=True, neg_weight=1.0),
    ])
    profiles = ev.build_user_profiles(train_df, model, negative_profile_weight=0.2)
    # positive centroid = (3*v1 + 1*v2)/4 = [0.75, 0.25, 0]
    # negative centroid = v3 = [0, 0, 1]
    # user = [0.75, 0.25, 0] - 0.2*[0,0,1] = [0.75, 0.25, -0.2], then L2-normalized.
    raw = np.array([0.75, 0.25, -0.2])
    expected = raw / np.linalg.norm(raw)
    assert np.allclose(profiles["u2"], expected, atol=1e-6)


def test_lambda_zero_ignores_negatives():
    model = _make_model([1, 2, 3])
    train_df = pd.DataFrame([
        _row("u1", 1, 1.0),
        _row("u1", 3, 0.0, negative=True, neg_weight=1.0),
    ])
    profiles = ev.build_user_profiles(train_df, model, negative_profile_weight=0.0)
    assert np.allclose(profiles["u1"], np.array([1.0, 0.0, 0.0]))


def test_validation_only_user_has_no_profile():
    """Profiles are built from train only - a user with only validation
    interactions must not have a profile and is therefore not evaluated."""
    model = _make_model([1, 2])
    train_df = pd.DataFrame([_row("u1", 1, 1.0)])
    profiles = ev.build_user_profiles(train_df, model, 0.0)
    assert "u1" in profiles
    assert "u_val_only" not in profiles


def test_test_interactions_never_enter_profiles():
    """test_incremental may add validation to the profile input, never test.
    Assert: adding the test row to the input changes nothing about that item
    unless it is actually passed in."""
    model = _make_model([1, 2, 3])
    train = pd.DataFrame([_row("u1", 1, 1.0)])
    val = pd.DataFrame([_row("u1", 2, 1.0)])
    test = pd.DataFrame([_row("u1", 3, 1.0)])
    incremental = ev.build_user_profiles(pd.concat([train, val]), model, 0.0)
    # Profile contains item1 + item2 features, item3 (test-only) is absent.
    assert abs(incremental["u1"][2]) < 1e-12
    assert incremental["u1"][1] > 0


# ------------------------------------------------------------- candidates
def test_candidates_exclude_owned_nsfw_and_out_of_window():
    items = pd.DataFrame([
        {"subject_id": 1, "air_date": "2026-02-01", "nsfw": False},
        {"subject_id": 2, "air_date": "2026-02-01", "nsfw": True},     # nsfw
        {"subject_id": 3, "air_date": "2026-05-01", "nsfw": False},    # beyond val window
        {"subject_id": 4, "air_date": None, "nsfw": False},            # unknown date
        {"subject_id": 5, "air_date": "2026-02-01", "nsfw": False},    # owned in train
    ])
    model = _make_model([1, 2, 3, 4, 5])
    candidates = ev.candidate_subject_ids(items, dt.date(2026, 3, 31), {5}, model)
    assert candidates == [1]


def test_subject_id_set_collects_all_evaluation_items():
    from run_content_baseline import subject_id_set

    validation = pd.DataFrame({"subject_id": [101, 102]})
    test = pd.DataFrame({"subject_id": [201, 202]})
    assert subject_id_set(validation, test) == {101, 102, 201, 202}


def test_group_excludes_history_per_user_not_globally():
    from run_content_baseline import evaluate_group

    model = _make_model([1, 2])
    train = pd.DataFrame([
        _row("u1", 2, 1.0),
        _row("u2", 1, 1.0),
    ])
    relevant = pd.DataFrame([
        {"anon_user_id": "u1", "subject_id": 1},
    ])
    result = evaluate_group(
        "validation_all",
        relevant,
        [1, 2],
        {"u1": np.asarray([1.0, 0.0])},
        model,
        [1, 2, 5],
        train,
    )
    assert result["status"] == "ok"
    assert result["eligible_positives"] == 1
    assert result["models"]["tfidf_content"]["recall@1"] == 1.0


# ------------------------------------------------------------- scoring
def test_scoring_and_stable_ties():
    model = _make_model([1, 2, 3])
    user_vec = np.zeros(3)
    user_vec[0] = 1.0
    ranked = ev.score_and_rank(user_vec, model, [3, 2, 1], 3)
    assert ranked[0] == 1
    assert ranked[1:] == [2, 3]  # zero scores tie -> ascending subject_id
    assert ev.score_and_rank(user_vec, model, [2, 3, 1], 3) == ranked  # input order irrelevant


def test_scoring_respects_k():
    model = _make_model([1, 2, 3])
    user_vec = np.zeros(3)
    user_vec[0] = 1.0
    assert ev.score_and_rank(user_vec, model, [1, 2, 3], 2) == [1, 2]
    assert ev.score_and_rank(user_vec, model, [], 5) == []


# ------------------------------------------------------------- insufficient
def test_insufficient_data_semantics():
    """No evaluable users (no train profiles) -> status insufficient_data,
    never a fabricated 0.0 score."""
    model = _make_model([1, 2])
    relevant = pd.DataFrame([
        {"anon_user_id": "ghost", "subject_id": 1},
    ])
    from run_content_baseline import evaluate_group
    result = evaluate_group(
        "validation_all", relevant, [1, 2], {}, model, [5, 10, 20], pd.DataFrame()
    )
    assert result["status"] == "insufficient_data"
    assert result["raw_users"] == 1
    assert result["raw_positives"] == 1
    assert result["users"] == 0
    assert result["eligible_positives"] == 0
    assert result["models"] == {}


def test_als_model_view_filters_completeness_and_loads_core(tmp_path):
    from run_als_baseline import select_model_view

    master = pd.DataFrame([
        {"anon_user_id": "complete", "subject_id": 1, "collection_complete": True},
        {"anon_user_id": "partial", "subject_id": 2, "collection_complete": False},
    ])
    selected = select_model_view(
        tmp_path, master, complete_only=True, view="all"
    )
    assert selected["subject_id"].tolist() == [1]

    for split_name, subject_id in (("train", 10), ("validation", 11), ("test", 12)):
        pd.DataFrame([{
            "anon_user_id": "complete",
            "subject_id": subject_id,
            "implicit_weight": 4.0,
            "split": split_name,
        }]).to_csv(tmp_path / f"{split_name}_core_interactions.csv", index=False)
    core = select_model_view(
        tmp_path, master, complete_only=True, view="core"
    )
    assert core["subject_id"].tolist() == [10, 11, 12]
    assert not core["is_negative"].any()


def test_als_cv_core_thresholds_are_fold_local():
    from run_als_cv import build_fold
    from src import weights
    from src.config import DatasetConfig

    cfg = DatasetConfig(interactions={
        "min_positive_interactions": 2,
        "core_min_item_support": 1,
    })
    frame = pd.DataFrame([
        {"anon_user_id": "u", "subject_id": 1,
         "updated_at": "2025-05-01T00:00:00Z",
         "feedback_tier": weights.FEEDBACK_REGULAR},
        {"anon_user_id": "u", "subject_id": 2,
         "updated_at": "2025-06-01T00:00:00Z",
         "feedback_tier": weights.FEEDBACK_STRONG},
        {"anon_user_id": "u", "subject_id": 1,
         "updated_at": "2025-08-01T00:00:00Z",
         "feedback_tier": weights.FEEDBACK_STRONG},
        # This user's validation event must not qualify their train profile.
        {"anon_user_id": "future-only", "subject_id": 1,
         "updated_at": "2025-08-01T00:00:00Z",
         "feedback_tier": weights.FEEDBACK_STRONG},
    ])
    train, validation, stats = build_fold(
        frame, {}, dt.date(2025, 6, 30), cfg, "core"
    )
    assert set(train["anon_user_id"]) == {"u"}
    assert set(validation["anon_user_id"]) == {"u"}
    assert stats["qualified_users"] == 1


def test_train_history_cap_is_recent_and_does_not_cap_validation():
    from src.model_views import cap_train_history

    frame = pd.DataFrame([
        {"anon_user_id": "u", "subject_id": 1, "split": "train",
         "updated_at": "2025-01-01T00:00:00Z"},
        {"anon_user_id": "u", "subject_id": 2, "split": "train",
         "updated_at": "2025-02-01T00:00:00Z"},
        {"anon_user_id": "u", "subject_id": 3, "split": "train",
         "updated_at": "2025-03-01T00:00:00Z"},
        {"anon_user_id": "u", "subject_id": 4, "split": "validation",
         "updated_at": "2026-01-01T00:00:00Z"},
        {"anon_user_id": "u", "subject_id": 5, "split": "validation",
         "updated_at": "2026-02-01T00:00:00Z"},
    ])
    selected = cap_train_history(frame, 2)
    assert set(selected[selected["split"] == "train"]["subject_id"]) == {2, 3}
    assert set(selected[selected["split"] == "validation"]["subject_id"]) == {4, 5}
