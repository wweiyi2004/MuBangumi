"""Implicit ALS matrix construction, fitting, ranking and persistence."""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

import numpy as np
import pandas as pd
from scipy import sparse
from threadpoolctl import threadpool_limits


@dataclass(frozen=True)
class IdMaps:
    user_ids: np.ndarray
    subject_ids: np.ndarray
    user_index: dict[str, int]
    item_index: dict[int, int]

    @classmethod
    def from_interactions(cls, interactions: pd.DataFrame) -> "IdMaps":
        user_ids = np.asarray(
            sorted(str(value) for value in interactions["anon_user_id"].unique()),
            dtype=str,
        )
        subject_ids = np.asarray(
            sorted(int(value) for value in interactions["subject_id"].unique()),
            dtype=np.int64,
        )
        return cls(
            user_ids=user_ids,
            subject_ids=subject_ids,
            user_index={value: index for index, value in enumerate(user_ids)},
            item_index={int(value): index for index, value in enumerate(subject_ids)},
        )


def build_confidence_matrix(
    interactions: pd.DataFrame,
    maps: IdMaps,
    *,
    negative_scale: float,
    recency_half_life_days: float = 0.0,
    reference_time: Any = None,
) -> sparse.csr_matrix:
    """Build user-item confidence matrix accepted by ``implicit``.

    Positive values are preferences with confidence.  Explicit dislikes use
    negative values, which ``implicit`` interprets as preference zero with the
    magnitude acting as confidence.  Missing entries remain unobserved.
    """
    if recency_half_life_days < 0:
        raise ValueError("recency_half_life_days must be >= 0")
    if recency_half_life_days > 0 and reference_time is None:
        raise ValueError("reference_time is required when recency decay is enabled")

    if recency_half_life_days > 0:
        reference = pd.Timestamp(reference_time)
        if reference.tzinfo is None:
            reference = reference.tz_localize("UTC")
        else:
            reference = reference.tz_convert("UTC")
        timestamps = pd.to_datetime(
            interactions["updated_at"], utc=True, errors="coerce"
        )
        ages = (reference - timestamps).dt.total_seconds() / 86400.0
        ages = ages.clip(lower=0).fillna(0.0).to_numpy(dtype=np.float64)
        recency_multipliers = np.power(
            0.5, ages / float(recency_half_life_days)
        )
    else:
        recency_multipliers = np.ones(len(interactions), dtype=np.float64)

    rows: list[int] = []
    columns: list[int] = []
    values: list[float] = []
    for row, recency_multiplier in zip(
        interactions.itertuples(index=False), recency_multipliers
    ):
        is_negative = bool(row.is_negative)
        if is_negative:
            value = (
                -float(row.negative_weight)
                * negative_scale
                * float(recency_multiplier)
            )
        else:
            value = float(row.implicit_weight) * float(recency_multiplier)
        if value == 0:
            continue
        rows.append(maps.user_index[str(row.anon_user_id)])
        columns.append(maps.item_index[int(row.subject_id)])
        values.append(value)
    matrix = sparse.coo_matrix(
        (np.asarray(values, dtype=np.float32), (rows, columns)),
        shape=(len(maps.user_ids), len(maps.subject_ids)),
        dtype=np.float32,
    ).tocsr()
    matrix.sum_duplicates()
    matrix.eliminate_zeros()
    return matrix


def fit_als(
    confidence: sparse.csr_matrix,
    cfg: Any,
    *,
    random_seed: int,
):
    from implicit.cpu.als import AlternatingLeastSquares

    # implicit parallelizes its own solver.  A second OpenBLAS thread pool
    # causes severe oversubscription on Windows, so keep BLAS single-threaded
    # during construction and fitting as recommended by the library.
    with threadpool_limits(limits=1, user_api="blas"):
        model = AlternatingLeastSquares(
            factors=cfg.factors,
            regularization=cfg.regularization,
            alpha=cfg.alpha,
            iterations=cfg.iterations,
            random_state=random_seed,
            calculate_training_loss=True,
        )
        model.fit(confidence, show_progress=False)
    return model


def rank_user(
    model: Any,
    maps: IdMaps,
    user_id: str,
    candidate_ids: Iterable[int],
    owned_ids: set[int],
    k: int,
) -> list[int]:
    """Rank one user's eligible candidates with stable subject-id ties."""
    user_row = maps.user_index.get(str(user_id))
    if user_row is None or k <= 0:
        return []
    eligible_ids = np.asarray(
        [
            int(subject_id)
            for subject_id in candidate_ids
            if int(subject_id) not in owned_ids
            and int(subject_id) in maps.item_index
        ],
        dtype=np.int64,
    )
    if eligible_ids.size == 0:
        return []
    item_rows = np.fromiter(
        (maps.item_index[int(subject_id)] for subject_id in eligible_ids),
        dtype=np.int64,
        count=len(eligible_ids),
    )
    scores = np.asarray(
        model.item_factors[item_rows] @ model.user_factors[user_row]
    ).ravel()
    scores = np.nan_to_num(scores, nan=-np.inf)
    order = np.lexsort((eligible_ids, -scores))
    return eligible_ids[order[:k]].tolist()


def save_model(
    model: Any,
    maps: IdMaps,
    directory: Path,
    metadata: dict[str, Any],
) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    model.save(directory / "model.npz")
    np.save(directory / "user_ids.npy", maps.user_ids)
    np.save(directory / "subject_ids.npy", maps.subject_ids)
    (directory / "model_meta.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
