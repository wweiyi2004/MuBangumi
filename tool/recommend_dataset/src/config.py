"""Configuration loading and validation for the dataset pipeline.

All relative paths in the config are resolved against the directory of the
config file itself, so the same config works no matter where it is invoked
from (e.g. via PowerShell from the repo root).
"""
from __future__ import annotations

import json
from datetime import date
from pathlib import Path
from typing import Any, Optional

from pydantic import BaseModel, Field, PrivateAttr, model_validator


class ApiConfig(BaseModel):
    base_url: str = "https://api.bgm.tv"
    user_agent: str = (
        "MuBangumiRecommendDataset/0.1.0 "
        "(recommendation dataset collection; personal use; low-rate public API access)"
    )
    timeout_seconds: float = 30.0
    max_concurrency: int = 2
    qps: float = 1.0
    max_retries: int = 5
    retry_base_seconds: float = 1.0
    retry_max_seconds: float = 30.0
    retry_jitter_seconds: float = 1.0

    @model_validator(mode="after")
    def _validate(self) -> "ApiConfig":
        if not self.base_url.startswith(("http://", "https://")):
            raise ValueError(f"api.base_url must start with http(s)://: {self.base_url!r}")
        if self.qps <= 0:
            raise ValueError("api.qps must be > 0")
        if self.max_concurrency < 1:
            raise ValueError("api.max_concurrency must be >= 1")
        if self.max_retries < 0:
            raise ValueError("api.max_retries must be >= 0")
        return self


class SubjectsConfig(BaseModel):
    seed_subject_ids: list[int] = []
    use_calendar: bool = True
    # [[year, quarter], ...] e.g. [[2026, 1], [2026, 2]]; quarter in 1..4
    year_quarters: list[list[int]] = []
    fetch_related: bool = True
    fetch_characters: bool = True
    fetch_persons: bool = False
    max_offset_per_query: int = 2000
    dry_run_max_subjects: int = 0

    @model_validator(mode="after")
    def _validate(self) -> "SubjectsConfig":
        for item in self.year_quarters:
            if len(item) != 2 or not (1 <= item[1] <= 4):
                raise ValueError(f"year_quarters entries must be [year, quarter(1..4)]: {item!r}")
        return self


class InteractionsConfig(BaseModel):
    collection_types: list[str] = ["wish", "doing", "collect", "on_hold", "dropped"]
    page_size: int = 100
    # Maximum pages fetched for one user in one invocation. Reaching this
    # budget marks the user truncated, never complete; rerunning resumes.
    max_pages_per_run: int = 0
    # Deprecated Phase-1 name retained so old local configs migrate without
    # silently losing their request budget.
    max_pages_per_type: int = 0
    dry_run_max_users: int = 0
    complete_only: bool = False
    min_positive_interactions: int = 0
    # Core ALS view: keep items with at least this many regular/strong train
    # interactions.  The all-positive files remain available for ablations.
    core_min_item_support: int = 3
    # Leakage-safe balancing cap applied independently inside each training
    # window. Validation/test relevance is never capped.
    max_train_interactions_per_user: int = 0

    @model_validator(mode="after")
    def _validate(self) -> "InteractionsConfig":
        from src.weights import COLLECTION_TYPE_ID

        for name in self.collection_types:
            if name not in COLLECTION_TYPE_ID:
                raise ValueError(
                    f"unknown collection_type {name!r}; expected one of {sorted(COLLECTION_TYPE_ID)}"
                )
        if not (1 <= self.page_size <= 100):
            raise ValueError("interactions.page_size must be within 1..100")
        if self.max_pages_per_run < 0 or self.max_pages_per_type < 0:
            raise ValueError("interaction page limits must be >= 0")
        if self.max_pages_per_run == 0 and self.max_pages_per_type > 0:
            self.max_pages_per_run = self.max_pages_per_type
        if self.min_positive_interactions < 0:
            raise ValueError("interactions.min_positive_interactions must be >= 0")
        if self.core_min_item_support < 1:
            raise ValueError("interactions.core_min_item_support must be >= 1")
        if self.max_train_interactions_per_user < 0:
            raise ValueError(
                "interactions.max_train_interactions_per_user must be >= 0"
            )
        return self


class SplitsConfig(BaseModel):
    train_end_date: date = date(2026, 6, 30)


class PrivacyConfig(BaseModel):
    salt_path: str = ""  # default: <data_dir>/salt.txt


class EvaluationConfig(BaseModel):
    """Offline evaluation settings.

    strict_temporal: when True, the content model may only use static /
    near-static content fields - dynamic popularity stats (score, rank,
    collection counts) are excluded because they are snapshot values that may
    contain post-cutoff information.

    allow_dynamic_popularity_features: opting in marks the dataset report with
    potential_feature_leakage = true.
    """

    strict_temporal: bool = True
    allow_dynamic_popularity_features: bool = False
    top_k: list[int] = [5, 10, 20]
    negative_profile_weight: float = 0.2
    random_seed: int = 42

    @model_validator(mode="after")
    def _validate(self) -> "EvaluationConfig":
        if self.negative_profile_weight < 0:
            raise ValueError("evaluation.negative_profile_weight must be >= 0")
        return self


class ContentModelConfig(BaseModel):
    summary_analyzer: str = "char"
    summary_ngram_min: int = 2
    summary_ngram_max: int = 4
    summary_min_df: int = 2
    # Feature group weights: tags/staff/summary/voice_actors/context.
    feature_weights: dict[str, float] = Field(
        default_factory=lambda: {
            "tags": 1.0,
            "staff": 0.8,
            "summary": 0.5,
            "voice_actors": 0.3,
            "context": 0.2,
        }
    )

    @model_validator(mode="after")
    def _validate(self) -> "ContentModelConfig":
        for name, weight in self.feature_weights.items():
            if weight < 0:
                raise ValueError(f"content_model.feature_weights.{name} must be >= 0")
        return self


class AlsModelConfig(BaseModel):
    """First-stage implicit ALS experiment settings.

    ``negative_scales`` defines validation-time ablations.  Zero trains on
    positive implicit feedback only; positive values encode explicit dislikes
    as negative confidence with the requested multiplier.
    """

    factors: int = 64
    regularization: float = 0.05
    alpha: float = 2.0
    iterations: int = 20
    negative_scales: list[float] = [0.0, 0.25]
    recency_half_life_days: float = 0.0

    @model_validator(mode="after")
    def _validate(self) -> "AlsModelConfig":
        if self.factors < 1:
            raise ValueError("als_model.factors must be >= 1")
        if self.regularization < 0:
            raise ValueError("als_model.regularization must be >= 0")
        if self.alpha <= 0:
            raise ValueError("als_model.alpha must be > 0")
        if self.iterations < 1:
            raise ValueError("als_model.iterations must be >= 1")
        if not self.negative_scales:
            raise ValueError("als_model.negative_scales must not be empty")
        if any(value < 0 for value in self.negative_scales):
            raise ValueError("als_model.negative_scales values must be >= 0")
        if self.recency_half_life_days < 0:
            raise ValueError("als_model.recency_half_life_days must be >= 0")
        return self


class OutputConfig(BaseModel):
    data_dir: str = "data"
    checkpoint_db: str = ""  # default: <data_dir>/checkpoints.sqlite
    failed_requests: str = ""  # default: <data_dir>/failed_requests.jsonl
    export_dir: str = ""  # default: <data_dir>/export
    baseline_dir: str = ""  # default: <data_dir>/baseline
    als_dir: str = ""  # default: <data_dir>/als


class DatasetConfig(BaseModel):
    api: ApiConfig = Field(default_factory=ApiConfig)
    subjects: SubjectsConfig = Field(default_factory=SubjectsConfig)
    interactions: InteractionsConfig = Field(default_factory=InteractionsConfig)
    splits: SplitsConfig = Field(default_factory=SplitsConfig)
    evaluation: EvaluationConfig = Field(default_factory=EvaluationConfig)
    content_model: ContentModelConfig = Field(default_factory=ContentModelConfig)
    als_model: AlsModelConfig = Field(default_factory=AlsModelConfig)
    privacy: PrivacyConfig = Field(default_factory=PrivacyConfig)
    output: OutputConfig = Field(default_factory=OutputConfig)

    _base_dir: Path = PrivateAttr(default=Path("."))

    def set_base_dir(self, path: Path) -> "DatasetConfig":
        self._base_dir = path
        return self

    def resolve(self, value: str | Path) -> Path:
        path = Path(value)
        if path.is_absolute():
            return path
        return (self._base_dir / path).resolve()

    @property
    def data_dir(self) -> Path:
        return self.resolve(self.output.data_dir)

    @property
    def checkpoint_db(self) -> Path:
        default = Path(self.output.data_dir) / "checkpoints.sqlite"
        return self.resolve(self.output.checkpoint_db or default)

    @property
    def failed_requests(self) -> Path:
        default = Path(self.output.data_dir) / "failed_requests.jsonl"
        return self.resolve(self.output.failed_requests or default)

    @property
    def export_dir(self) -> Path:
        default = Path(self.output.data_dir) / "export"
        return self.resolve(self.output.export_dir or default)

    @property
    def baseline_dir(self) -> Path:
        default = Path(self.output.data_dir) / "baseline"
        return self.resolve(self.output.baseline_dir or default)

    @property
    def als_dir(self) -> Path:
        default = Path(self.output.data_dir) / "als"
        return self.resolve(self.output.als_dir or default)

    @property
    def salt_path(self) -> Path:
        default = Path(self.output.data_dir) / "salt.txt"
        return self.resolve(self.privacy.salt_path or default)

    @property
    def seed_users_path(self) -> Path:
        return self.resolve("seed_users.txt")


def load_config(path: str | Path) -> DatasetConfig:
    """Load and validate a JSON config file."""
    config_file = Path(path)
    raw: Any = json.loads(config_file.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"config root must be a JSON object: {config_file}")
    cfg = DatasetConfig.model_validate(raw)
    cfg.set_base_dir(config_file.resolve().parent)
    return cfg
