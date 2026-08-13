"""Implicit feedback weighting for ALS-style recommenders.

Collection weights (spec):
  wish 1.0, doing 3.0, collect/done 4.0, on_hold 0.25
  dropped is NOT a positive sample; negative_weight = 1.0

Rating correction (spec):
  unrated               -> multiplier 1.0
  1..4                  -> not positive feedback; negative_weight = (5-rate)/4
  5..6                  -> multiplier 0.7
  7..8                  -> multiplier 1.0
  9..10                 -> multiplier 1.3

implicit_weight = collection_weight * rating_multiplier  (positives only)

Feedback tiers used by the cleaned views:
  strong_positive  explicit rating >= 7
  regular_positive collect/doing with no strong explicit rating
  weak_positive    wish/on_hold with no strong explicit rating
  negative         dropped or explicit rating 1..4

Resolutions (documented in README):
  * dropped + rated 1..4 -> the rating's negative_weight wins (more informative)
  * dropped + rated 5..10-> still negative, negative_weight = 1.0
  * out-of-range rates are clamped to 0..10
  * missing interactions are never treated as negative feedback (nothing here
    is synthesized from absence)
"""
from __future__ import annotations

from typing import Optional

COLLECTION_TYPE_ID = {
    "wish": 1,
    "collect": 2,  # "done / 看过"
    "doing": 3,
    "on_hold": 4,
    "dropped": 5,
}
COLLECTION_TYPE_NAME = {value: key for key, value in COLLECTION_TYPE_ID.items()}

COLLECTION_WEIGHT = {1: 1.0, 3: 3.0, 2: 4.0, 4: 0.25}

FEEDBACK_STRONG = "strong_positive"
FEEDBACK_REGULAR = "regular_positive"
FEEDBACK_WEAK = "weak_positive"
FEEDBACK_NEGATIVE = "negative"


def clamp_rate(rate: Optional[int]) -> int:
    """Normalize a rating to 0..10 (None -> 0)."""
    if rate is None:
        return 0
    return min(10, max(0, int(rate)))


def rating_multiplier(rate: Optional[int]) -> Optional[float]:
    """None means the rating makes the interaction negative feedback."""
    rating = clamp_rate(rate)
    if rating == 0:
        return 1.0
    if rating <= 4:
        return None
    if rating <= 6:
        return 0.7
    if rating <= 8:
        return 1.0
    return 1.3


def is_negative_feedback(collection_type: int, rate: Optional[int]) -> bool:
    return collection_type == COLLECTION_TYPE_ID["dropped"] or clamp_rate(rate) in (1, 2, 3, 4)


def negative_weight(collection_type: int, rate: Optional[int]) -> float:
    """0.0 for rows that are not negatives; (5-rate)/4 for 1..4 stars; dropped -> 1.0."""
    rating = clamp_rate(rate)
    if rating in (1, 2, 3, 4):
        return (5 - rating) / 4.0
    if collection_type == COLLECTION_TYPE_ID["dropped"]:
        return 1.0
    return 0.0


def feedback_tier(collection_type: int, rate: Optional[int]) -> str:
    """Map a collection row to an explicit, auditable feedback tier."""
    rating = clamp_rate(rate)
    if is_negative_feedback(collection_type, rating):
        return FEEDBACK_NEGATIVE
    if rating >= 7:
        return FEEDBACK_STRONG
    if collection_type in (
        COLLECTION_TYPE_ID["collect"],
        COLLECTION_TYPE_ID["doing"],
    ):
        return FEEDBACK_REGULAR
    return FEEDBACK_WEAK


def classify_interaction(collection_type: int, rate: Optional[int]) -> dict:
    rating = clamp_rate(rate)
    negative = is_negative_feedback(collection_type, rating)
    multiplier = None if negative else rating_multiplier(rating)
    collection_weight = COLLECTION_WEIGHT.get(collection_type, 0.0)
    tier = feedback_tier(collection_type, rating)
    positive_confidence = round(collection_weight * (multiplier or 1.0), 6)
    negative_confidence = negative_weight(collection_type, rating)
    return {
        "is_negative": negative,
        "feedback_tier": tier,
        "preference": -1 if negative else 1,
        "is_strong_positive": tier == FEEDBACK_STRONG,
        "is_weak_positive": tier == FEEDBACK_WEAK,
        "collection_weight": collection_weight,
        "rating_multiplier": multiplier,
        "implicit_weight": 0.0 if negative else positive_confidence,
        "negative_weight": negative_confidence,
        "confidence_weight": negative_confidence if negative else positive_confidence,
    }
