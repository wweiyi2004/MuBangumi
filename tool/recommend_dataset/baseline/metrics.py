"""Offline ranking metrics (binary relevance, per-user then averaged)."""
from __future__ import annotations

import math
from typing import Iterable, Optional


def recall_at_k(ranked: list[int], relevant: set[int], k: int) -> float:
    if not relevant:
        return 0.0
    hits = sum(1 for sid in ranked[:k] if sid in relevant)
    return hits / len(relevant)


def precision_at_k(ranked: list[int], relevant: set[int], k: int) -> float:
    if k <= 0:
        return 0.0
    hits = sum(1 for sid in ranked[:k] if sid in relevant)
    return hits / k


def f1_at_k(ranked: list[int], relevant: set[int], k: int) -> float:
    precision = precision_at_k(ranked, relevant, k)
    recall = recall_at_k(ranked, relevant, k)
    if precision + recall == 0:
        return 0.0
    return 2.0 * precision * recall / (precision + recall)


def ndcg_at_k(ranked: list[int], relevant: set[int], k: int) -> float:
    if not relevant:
        return 0.0
    hits = 0
    dcg = 0.0
    for position, sid in enumerate(ranked[:k], start=1):
        if sid in relevant:
            hits += 1
            dcg += 1.0 / math.log2(position + 1)
    ideal = sum(1.0 / math.log2(pos + 1) for pos in range(1, min(k, len(relevant)) + 1))
    return dcg / ideal if ideal > 0 else 0.0


def hit_rate_at_k(ranked: list[int], relevant: set[int], k: int) -> float:
    return 1.0 if any(sid in relevant for sid in ranked[:k]) else 0.0


def mrr_at_k(ranked: list[int], relevant: set[int], k: int) -> float:
    for position, sid in enumerate(ranked[:k], start=1):
        if sid in relevant:
            return 1.0 / position
    return 0.0


def per_user_metrics(
    ranked: list[int], relevant: set[int], top_k: Iterable[int]
) -> dict[str, float]:
    # Empty top_k falls back to the legacy default so a bad configuration
    # cannot crash metric collection (IndexError on top_k[0]).
    top_k = list(top_k) or [10]
    metrics: dict[str, float] = {}
    for k in top_k:
        metrics[f"precision@{k}"] = precision_at_k(ranked, relevant, k)
        metrics[f"recall@{k}"] = recall_at_k(ranked, relevant, k)
        metrics[f"f1@{k}"] = f1_at_k(ranked, relevant, k)
        metrics[f"ndcg@{k}"] = ndcg_at_k(ranked, relevant, k)
    metrics[f"hit_rate@{top_k[1] if len(top_k) > 1 else top_k[0]}"] = hit_rate_at_k(
        ranked, relevant, top_k[1] if len(top_k) > 1 else top_k[0]
    )
    metrics[f"mrr@{top_k[-1]}"] = mrr_at_k(ranked, relevant, top_k[-1])
    return metrics


def mean_metrics(per_user: list[dict[str, float]], top_k: Iterable[int]) -> dict[str, float]:
    if not per_user:
        return {}
    result: dict[str, float] = {}
    for key in per_user[0]:
        result[key] = round(sum(row[key] for row in per_user) / len(per_user), 6)
    return result


def catalog_coverage_at_k(
    ranked_lists: list[list[int]], total_candidates: int, k: int
) -> float:
    """Fraction of the candidate catalog covered by the top-k of any user."""
    if not ranked_lists or total_candidates <= 0:
        return 0.0
    covered = {sid for ranked in ranked_lists for sid in ranked[:k]}
    return round(len(covered) / total_candidates, 6)
