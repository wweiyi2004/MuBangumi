"""Leakage-safe interaction view transformations shared by export and CV."""
from __future__ import annotations

import pandas as pd


def cap_train_history(
    frame: pd.DataFrame,
    max_per_user: int,
    *,
    split_column: str = "split",
) -> pd.DataFrame:
    """Keep each user's most recent N rows inside the train window only.

    The cap is fold-local: validation/test rows do not affect which historical
    training rows survive, and relevance rows are never capped.
    """
    if frame.empty or max_per_user <= 0:
        return frame.copy()
    working = frame.copy()
    working["_model_view_order"] = range(len(working))
    train = working[working[split_column] == "train"].copy()
    other = working[working[split_column] != "train"].copy()
    train["_model_view_updated"] = pd.to_datetime(
        train["updated_at"], utc=True, errors="coerce"
    )
    train = train.sort_values(
        ["anon_user_id", "_model_view_updated", "subject_id"],
        ascending=[True, False, True],
        kind="mergesort",
        na_position="last",
    )
    train = train.groupby("anon_user_id", sort=False).head(max_per_user)
    selected = pd.concat([train, other], ignore_index=False)
    selected = selected.sort_values("_model_view_order", kind="mergesort")
    return selected.drop(
        columns=["_model_view_order", "_model_view_updated"],
        errors="ignore",
    )
