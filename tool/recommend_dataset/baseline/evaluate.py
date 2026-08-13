"""User profiles, candidate sets and scoring for the content baseline.

Temporal discipline:
- user profiles are built ONLY from train-window interactions
- validation/test ground truth never enters a profile used for the window
  before it (test_incremental profiles may use train + validation, never test)
- candidates are filtered by air date <= the evaluation window end; each user
  excludes only their own prior interactions during ranking
"""
from __future__ import annotations

import datetime as dt
from typing import Any, Optional

import numpy as np
import pandas as pd
from scipy import sparse
from sklearn.preprocessing import normalize

from src.parse import parse_date_flexible


def _centroid(model, rows_df: pd.DataFrame, weight_col: str) -> Optional[np.ndarray]:
    """Weighted-mean item vector over the given rows; None if nothing usable."""
    if rows_df.empty:
        return None
    indices: list[int] = []
    weights: list[float] = []
    for _, row in rows_df.iterrows():
        idx = model.item_row(int(row["subject_id"]))
        if idx is None:
            continue
        indices.append(idx)
        weights.append(float(row[weight_col]))
    if not indices or sum(weights) <= 0:
        return None
    sub = model.matrix[indices].multiply(np.asarray(weights).reshape(-1, 1))
    return np.asarray(sub.sum(axis=0)).ravel() / sum(weights)


def build_user_profiles(
    train_df: pd.DataFrame,
    model,
    negative_profile_weight: float = 0.2,
) -> dict[str, np.ndarray]:
    """Weighted-mean user profiles from train interactions only.

    user_vector = positive_centroid - lambda * negative_centroid
    where positive uses implicit_weight and negative uses negative_weight
    (dropped / 1..4 star rows). Output vectors are L2-normalized.
    """
    profiles: dict[str, np.ndarray] = {}
    for user, group in train_df.groupby("anon_user_id", sort=True):
        positive = group[~group["is_negative"].astype(bool)]
        negative = group[group["is_negative"].astype(bool)]
        pos_centroid = _centroid(model, positive, "implicit_weight")
        if pos_centroid is None:
            continue
        vector = pos_centroid
        if negative_profile_weight > 0:
            neg_centroid = _centroid(model, negative, "negative_weight")
            if neg_centroid is not None:
                vector = pos_centroid - negative_profile_weight * neg_centroid
        norm = np.linalg.norm(vector)
        if norm == 0:
            continue
        profiles[str(user)] = normalize(vector.reshape(1, -1), norm="l2")[0].ravel()
    return profiles


def candidate_subject_ids(
    items_df: pd.DataFrame,
    window_end: dt.date,
    train_owned: set[int],
    model,
    exclude_nsfw: bool = True,
) -> list[int]:
    """Candidates: air_date <= window end, non-nsfw, not owned in train."""
    result: list[int] = []
    for _, row in items_df.iterrows():
        sid = int(row["subject_id"])
        if sid in train_owned:
            continue
        nsfw = row.get("nsfw", False)
        if exclude_nsfw and not pd.isna(nsfw) and bool(nsfw):
            continue
        air = parse_date_flexible(row.get("air_date"))
        if air is None or air > window_end:
            continue
        if model.item_row(sid) is None:
            continue
        result.append(sid)
    return result


def score_and_rank(
    user_vector: np.ndarray,
    model,
    candidate_ids: list[int],
    k: int,
) -> list[int]:
    """Cosine-ish ranking (vectors are L2-normalized) with stable ties.

    Ties are broken by ascending subject_id for reproducibility.
    """
    if not candidate_ids:
        return []
    matrix, ids = model.submatrix(candidate_ids)
    scores = np.asarray(user_vector @ matrix.T).ravel()
    order = np.lexsort((ids, -scores))  # primary: -score, secondary: id ascending
    ranked = ids[order].tolist()
    return ranked[:k]


def score_matrix_and_rank(
    user_vector: np.ndarray,
    matrix: sparse.csr_matrix,
    subject_ids: np.ndarray,
    excluded_ids: set[int],
    k: int,
) -> list[int]:
    """Rank a prebuilt candidate matrix after per-user exclusions."""
    if matrix.shape[0] == 0 or k <= 0:
        return []
    scores = np.asarray(user_vector @ matrix.T).ravel()
    if excluded_ids:
        mask = np.fromiter(
            (int(subject_id) not in excluded_ids for subject_id in subject_ids),
            dtype=bool,
            count=len(subject_ids),
        )
        scores = scores[mask]
        subject_ids = subject_ids[mask]
    order = np.lexsort((subject_ids, -scores))
    return subject_ids[order[:k]].tolist()
