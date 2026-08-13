"""Implicit feedback weights per the dataset spec."""
from __future__ import annotations

import pytest

from src import weights

WISH = 1
DONE = 2
DOING = 3
ON_HOLD = 4
DROPPED = 5


def test_collection_weights():
    assert weights.COLLECTION_WEIGHT[WISH] == 1.0
    assert weights.COLLECTION_WEIGHT[DOING] == 3.0
    assert weights.COLLECTION_WEIGHT[DONE] == 4.0
    assert weights.COLLECTION_WEIGHT[ON_HOLD] == 0.25
    assert DROPPED not in weights.COLLECTION_WEIGHT  # dropped is never a positive


def test_rating_multiplier_bands():
    assert weights.rating_multiplier(0) == 1.0
    assert weights.rating_multiplier(None) == 1.0
    assert weights.rating_multiplier(1) is None
    assert weights.rating_multiplier(4) is None
    assert weights.rating_multiplier(5) == 0.7
    assert weights.rating_multiplier(6) == 0.7
    assert weights.rating_multiplier(7) == 1.0
    assert weights.rating_multiplier(8) == 1.0
    assert weights.rating_multiplier(9) == 1.3
    assert weights.rating_multiplier(10) == 1.3


def test_implicit_weight_examples():
    assert weights.classify_interaction(DOING, 7)["implicit_weight"] == pytest.approx(3.0)
    assert weights.classify_interaction(DONE, 9)["implicit_weight"] == pytest.approx(5.2)
    assert weights.classify_interaction(WISH, 0)["implicit_weight"] == pytest.approx(1.0)
    assert weights.classify_interaction(ON_HOLD, 5)["implicit_weight"] == pytest.approx(0.175)
    assert weights.classify_interaction(WISH, 6)["implicit_weight"] == pytest.approx(0.7)


def test_rating_1to4_is_negative():
    result = weights.classify_interaction(DONE, 2)
    assert result["is_negative"] is True
    assert result["implicit_weight"] == 0.0
    assert result["negative_weight"] == pytest.approx(0.75)  # (5-2)/4


def test_dropped_is_negative_with_weight_one():
    result = weights.classify_interaction(DROPPED, 0)
    assert result["is_negative"] is True
    assert result["implicit_weight"] == 0.0
    assert result["negative_weight"] == 1.0


def test_dropped_with_good_rating_still_negative():
    result = weights.classify_interaction(DROPPED, 7)
    assert result["is_negative"] is True
    assert result["implicit_weight"] == 0.0
    assert result["negative_weight"] == 1.0


def test_dropped_rated_1to4_uses_rating_weight():
    result = weights.classify_interaction(DROPPED, 2)
    assert result["is_negative"] is True
    assert result["negative_weight"] == pytest.approx(0.75)  # rating more informative


def test_out_of_range_rate_clamped():
    assert weights.clamp_rate(11) == 10
    assert weights.clamp_rate(-3) == 0
    assert weights.classify_interaction(DOING, 11)["implicit_weight"] == pytest.approx(3.9)


def test_absence_is_not_negative():
    # An unrated wish is a weak positive, never synthesized negative feedback.
    assert weights.negative_weight(WISH, 0) == 0.0
    assert weights.is_negative_feedback(DOING, 0) is False


def test_type_name_roundtrip():
    assert weights.COLLECTION_TYPE_NAME[weights.COLLECTION_TYPE_ID["on_hold"]] == "on_hold"
    assert weights.COLLECTION_TYPE_ID["collect"] == DONE


@pytest.mark.parametrize(
    ("collection_type", "rate", "tier"),
    [
        (DONE, 8, weights.FEEDBACK_STRONG),
        (DOING, 0, weights.FEEDBACK_REGULAR),
        (DONE, 6, weights.FEEDBACK_REGULAR),
        (WISH, 0, weights.FEEDBACK_WEAK),
        (ON_HOLD, 6, weights.FEEDBACK_WEAK),
        (DROPPED, 9, weights.FEEDBACK_NEGATIVE),
        (DONE, 2, weights.FEEDBACK_NEGATIVE),
    ],
)
def test_feedback_tiers(collection_type, rate, tier):
    result = weights.classify_interaction(collection_type, rate)
    assert result["feedback_tier"] == tier
    assert result["preference"] == (-1 if tier == weights.FEEDBACK_NEGATIVE else 1)
    assert result["confidence_weight"] == pytest.approx(
        result["negative_weight"] if result["is_negative"] else result["implicit_weight"]
    )
