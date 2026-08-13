"""Content features for the TF-IDF baseline.

Design constraints:
- sparse matrices only (never a dense item x item similarity matrix)
- Chinese summaries use character n-grams (analyzer="char") - whitespace
  tokenization would produce nothing useful for Chinese text
- categorical features are namespaced tokens, e.g. tag:治愈, staff:京都动画,
  director:山田尚子, actor:早见沙织
- strict temporal mode (default) uses ONLY static / near-static fields;
  dynamic popularity stats (score/rank/collection counts) are snapshot values
  that may contain post-cutoff information and are excluded
"""
from __future__ import annotations

from typing import Any, Optional

import numpy as np
import pandas as pd
from scipy import sparse
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.preprocessing import MultiLabelBinarizer, normalize

# Snapshot popularity stats - strictly excluded unless the user opts in.
DYNAMIC_COLUMNS = {
    "score", "rank", "rating_total", "collection_total",
    "wish_count", "doing_count", "collect_count",
    "on_hold_count", "dropped_count",
}

SEASON_NAMES = {1: "winter", 2: "spring", 3: "summer", 4: "autumn"}

# Feature group -> (item_features.jsonl columns, token namespace prefix)
CATEGORICAL_GROUPS = {
    "tags": (["tags", "meta_tags"], "tag"),
    "staff": (["production", "director", "series_composer", "original_work", "music"], "staff"),
    "voice_actors": (["voice_actors"], "actor"),
}


def _tokens_for(values: Any, prefix: str) -> list[str]:
    if not isinstance(values, list):
        return []
    return [f"{prefix}:{str(v).strip()}" for v in values if v and str(v).strip()]


def episode_count_bucket(count: Any) -> Optional[str]:
    if count is None:
        return None
    try:
        value = int(count)
    except (TypeError, ValueError):
        return None
    if value <= 0:
        return None
    if value <= 12:
        return "1-12"
    if value <= 24:
        return "13-24"
    return "25+"


def _dynamic_tokens_for(row: pd.Series) -> list[str]:
    """Coarse buckets over snapshot popularity stats (opt-in only)."""
    tokens: list[str] = []
    score = row.get("score")
    if score is not None and score > 0:
        bucket = "0-2" if score < 3 else ("3-5" if score < 6 else ("6-8" if score < 9 else "9-10"))
        tokens.append(f"dyn:score:{bucket}")
    rank = row.get("rank")
    if rank is not None and rank > 0:
        bucket = "top100" if rank <= 100 else ("top1000" if rank <= 1000 else ("top3000" if rank <= 3000 else "rest"))
        tokens.append(f"dyn:rank:{bucket}")
    total = row.get("collection_total")
    if total is not None and total > 0:
        bucket = "lt100" if total < 100 else ("lt1000" if total < 1000 else ("lt10000" if total < 10000 else "10k+"))
        tokens.append(f"dyn:collection:{bucket}")
    return tokens


def build_feature_matrix(
    items: pd.DataFrame, cfg: Any, strict: bool = True
) -> dict[str, Any]:
    """Build the sparse L2-normalized item feature matrix.

    Returns {"matrix": csr, "subject_ids": np.ndarray, "feature_names": list, "meta": dict}.
    """
    subject_ids = items["subject_id"].astype(int).to_numpy()
    blocks: list[sparse.csr_matrix] = []
    feature_names: list[str] = []
    meta: dict[str, Any] = {}

    # ---- categorical groups (MultiLabelBinarizer, weighted) ----
    for group_name, (columns, prefix) in CATEGORICAL_GROUPS.items():
        weight = float(cfg.feature_weights.get(group_name, 1.0))
        token_lists: list[list[str]] = []
        for _, row in items.iterrows():
            tokens: list[str] = []
            for col in columns:
                tokens.extend(_tokens_for(row.get(col), prefix))
            token_lists.append(tokens)
        mlb = MultiLabelBinarizer(sparse_output=True)
        block = mlb.fit_transform(token_lists)
        if weight != 1.0:
            block = block * weight
        blocks.append(block)
        feature_names.extend(mlb.classes_.tolist())
        meta[f"{group_name}_features"] = int(len(mlb.classes_))

    # ---- context extras: platform, episode bucket, year/season, relations ----
    extra_token_lists: list[list[str]] = []
    for _, row in items.iterrows():
        tokens: list[str] = []
        platform = row.get("platform")
        if platform:
            tokens.append(f"ctx:platform:{platform}")
        bucket = episode_count_bucket(row.get("episode_count"))
        if bucket:
            tokens.append(f"ctx:eps:{bucket}")
        year = row.get("year")
        if year is not None:
            try:
                tokens.append(f"ctx:year:{int(year)}")
            except (TypeError, ValueError):
                pass
        season = row.get("season")
        if season in SEASON_NAMES:
            tokens.append(f"ctx:season:{SEASON_NAMES[season]}")
        for entry in row.get("related_prequel_sequel") or []:
            if isinstance(entry, dict):
                tokens.append(f"rel:{entry.get('relation')}:{entry.get('id')}")
        extra_token_lists.append(tokens)
    if any(extra_token_lists):
        mlb = MultiLabelBinarizer(sparse_output=True)
        block = mlb.fit_transform(extra_token_lists)
        weight = float(cfg.feature_weights.get("context", 0.2))
        if weight != 1.0:
            block = block * weight
        blocks.append(block)
        feature_names.extend(mlb.classes_.tolist())
        meta["context_features"] = int(len(mlb.classes_))

    # ---- summary text: Chinese-safe character n-grams ----
    summaries = [str(row.get("summary") or "").strip() for _, row in items.iterrows()]
    if any(summaries):
        try:
            vectorizer = TfidfVectorizer(
                analyzer=cfg.summary_analyzer,
                ngram_range=(cfg.summary_ngram_min, cfg.summary_ngram_max),
                min_df=cfg.summary_min_df,
            )
            block = vectorizer.fit_transform(summaries)
            weight = float(cfg.feature_weights.get("summary", 0.5))
            if weight != 1.0:
                block = block * weight
            blocks.append(block)
            feature_names.extend(vectorizer.get_feature_names_out().tolist())
            meta["summary_vocab_size"] = int(len(vectorizer.vocabulary_))
        except ValueError:
            # min_df filtered everything out - empty vocabulary, skip silently.
            meta["summary_vocab_size"] = 0

    # ---- dynamic popularity stats (only when the user explicitly opts in) ----
    if not strict:
        dyn_lists: list[list[str]] = []
        for _, row in items.iterrows():
            dyn_lists.append(_dynamic_tokens_for(row))
        if any(dyn_lists):
            mlb = MultiLabelBinarizer(sparse_output=True)
            block = mlb.fit_transform(dyn_lists)
            blocks.append(block)
            feature_names.extend(mlb.classes_.tolist())
            meta["dynamic_features"] = int(len(mlb.classes_))

    if not blocks:
        raise ValueError("no content features could be built (all fields empty)")

    matrix = sparse.hstack(blocks, format="csr")
    matrix = normalize(matrix, norm="l2", axis=1)
    meta["n_items"] = int(matrix.shape[0])
    meta["n_features"] = int(matrix.shape[1])
    return {
        "matrix": matrix,
        "subject_ids": subject_ids,
        "feature_names": feature_names,
        "meta": meta,
    }
