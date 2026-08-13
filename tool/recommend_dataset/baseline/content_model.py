"""TF-IDF content model: sparse item feature matrix with persistence.

The item x feature matrix is sparse (scipy csr). Scoring is done with sparse
matrix products - no dense item x item similarity matrix is ever built.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from scipy import sparse

from baseline.features import build_feature_matrix


class ContentModel:
    def __init__(
        self,
        matrix: sparse.csr_matrix,
        subject_ids: np.ndarray,
        feature_names: list[str],
        meta: dict[str, Any],
    ) -> None:
        self.matrix = matrix
        self.subject_ids = np.asarray(subject_ids)
        self.feature_names = list(feature_names)
        self.meta = meta
        self._index = {int(sid): i for i, sid in enumerate(self.subject_ids)}

    # ------------------------------------------------------------- construction
    @classmethod
    def fit(cls, items: pd.DataFrame, cfg: Any, strict: bool = True) -> "ContentModel":
        result = build_feature_matrix(items, cfg, strict=strict)
        return cls(**result)

    # ----------------------------------------------------------------- access
    def item_row(self, subject_id: int) -> int | None:
        return self._index.get(int(subject_id))

    def item_vector(self, subject_id: int):
        idx = self.item_row(subject_id)
        if idx is None:
            return None
        return self.matrix.getrow(idx)

    def submatrix(self, ids: list[int]) -> tuple[sparse.csr_matrix, np.ndarray]:
        """Matrix rows + ids for the given subject ids (only known ones)."""
        rows = [idx for idx in (self._index.get(int(sid)) for sid in ids) if idx is not None]
        if not rows:
            return sparse.csr_matrix((0, self.matrix.shape[1])), np.asarray([], dtype=int)
        return self.matrix[rows], self.subject_ids[rows]

    # ------------------------------------------------------------- persistence
    def save(self, directory: Path) -> None:
        directory.mkdir(parents=True, exist_ok=True)
        sparse.save_npz(directory / "feature_matrix.npz", self.matrix)
        np.save(directory / "subject_ids.npy", self.subject_ids)
        meta = {"feature_names": self.feature_names, **self.meta}
        (directory / "model_meta.json").write_text(
            json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8"
        )

    @classmethod
    def load(cls, directory: Path) -> "ContentModel":
        matrix = sparse.load_npz(directory / "feature_matrix.npz")
        subject_ids = np.load(directory / "subject_ids.npy")
        meta = json.loads((directory / "model_meta.json").read_text(encoding="utf-8"))
        feature_names = meta.pop("feature_names")
        return cls(matrix, subject_ids, feature_names, meta)
