"""End-to-end export: file completeness, field integrity, split correctness."""
from __future__ import annotations

import datetime as dt
import json

import pandas as pd
import pytest

from src import export, weights
from src.config import DatasetConfig


def _cfg(tmp_path, train_end="2025-12-31"):
    cfg = DatasetConfig(
        splits={"train_end_date": train_end},
        output={"data_dir": "data"},
    )
    cfg.set_base_dir(tmp_path)
    return cfg


def _subject(sid, name, air_date, tags=True, platform="TV", infobox=True):
    record = {
        "subject_id": sid, "name": name, "name_cn": f"中文{name}",
        "air_date": air_date, "platform": platform, "episode_count": 12,
        "summary": "简介", "fetched_at": "2026-01-01T00:00:00Z",
    }
    if tags:
        record["tags_json"] = json.dumps(["恋爱"], ensure_ascii=False)
    if infobox:
        record["infobox_json"] = json.dumps({"动画制作": ["示例公司"]}, ensure_ascii=False)
    record["meta_tags_json"] = json.dumps(["TV"], ensure_ascii=False)
    record["production_json"] = json.dumps(["示例公司"], ensure_ascii=False)
    record["director_json"] = json.dumps(["示例监督"], ensure_ascii=False)
    record["voice_actors_json"] = json.dumps(["示例声优"], ensure_ascii=False)
    record["related_json"] = json.dumps(
        [{"id": 990001, "relation": "续作", "name": "x", "type": 2}], ensure_ascii=False
    )
    return record


def _interaction(anon, sid, ctype, rate, updated="2025-06-01T00:00:00+08:00"):
    # Default: UTC 2025-05-31T16:00Z -> train. Pass updated=None for missing.
    return {
        "anon_user_id": anon, "subject_id": sid,
        "collection_type": ctype,
        "collection_type_name": weights.COLLECTION_TYPE_NAME[ctype],
        "user_rating": rate,
        "updated_at": updated,
        "fetched_at": "2026-01-01T00:00:00Z",
    }


def test_export_files_and_fields(tmp_path, store):
    store.upsert_subject(_subject(456001, "训练条目", "2025-03-01"))
    store.upsert_subject(_subject(456002, "验证条目", "2026-01-15"))
    store.upsert_subject(_subject(456003, "测试条目", "2026-04-01"))
    store.upsert_subject(_subject(456004, "无日期条目", None, tags=False, infobox=False))
    store.upsert_subject(_subject(456005, "窗口外条目", "2026-07-01"))
    for sid in (456001, 456002, 456003, 456004, 456005):
        store.mark_subject_status(sid, "ok")

    # Temporal splits are driven by updated_at (UTC):
    # 2025-06-01+08:00 -> train; 2026-02-01+08:00 -> validation; 2026-05-01+08:00 -> test.
    store.upsert_interaction(_interaction("u" * 64, 456001, weights.COLLECTION_TYPE_ID["wish"], 7,
                                          updated="2025-06-01T00:00:00+08:00"))
    store.upsert_interaction(_interaction("v" * 64, 456002, weights.COLLECTION_TYPE_ID["doing"], 0,
                                          updated="2026-02-01T10:00:00+08:00"))
    store.upsert_interaction(_interaction("w" * 64, 456003, weights.COLLECTION_TYPE_ID["collect"], 9,
                                          updated="2026-05-01T10:00:00+08:00"))
    store.upsert_interaction(_interaction("x" * 64, 456001, weights.COLLECTION_TYPE_ID["dropped"], 0,
                                          updated="2025-06-01T00:00:00+08:00"))
    # Invalid reference: subject 999000 was never collected.
    store.upsert_interaction(_interaction("y" * 64, 999000, weights.COLLECTION_TYPE_ID["on_hold"], 0,
                                          updated="2025-06-01T00:00:00+08:00"))

    cfg = _cfg(tmp_path)
    report = export.build_export(store, cfg)

    expected_files = [
        "subjects.csv", "interactions.csv", "train_interactions.csv",
        "validation_interactions.csv", "test_interactions.csv",
        "item_features.jsonl", "dataset_report.json",
    ]
    for name in expected_files:
        assert (cfg.export_dir / name).exists(), name

    # ---- interactions.csv: ALS keeps metadata-missing anime ids
    master = pd.read_csv(cfg.export_dir / "interactions.csv", encoding="utf-8")
    assert set(master.columns) == set(export.INTERACTION_MASTER_COLUMNS)
    assert len(master) == 5
    assert report["interactions"]["total_raw"] == 5
    assert report["interactions"]["total"] == 5
    assert report["interactions"]["invalid_refs"] == 1
    assert report["interactions"]["users"] == 5
    assert report["interactions"]["sparsity"] == pytest.approx(1 - 5 / (5 * 4), abs=1e-6)
    assert report["interactions"]["rated_ratio"] == pytest.approx(0.4)

    dropped = master[master["collection_type_name"] == "dropped"].iloc[0]
    assert bool(dropped["is_negative"]) is True
    assert dropped["negative_weight"] == 1.0
    assert dropped["implicit_weight"] == 0.0

    # ---- split files: positives only, temporal split, no future leakage
    train = pd.read_csv(cfg.export_dir / "train_interactions.csv", encoding="utf-8")
    assert list(train.columns) == export.SPLIT_COLUMNS
    assert set(train["subject_id"]) == {456001, 999000}
    assert set(train["collection_type_name"]) == {"wish", "on_hold"}

    val = pd.read_csv(cfg.export_dir / "validation_interactions.csv", encoding="utf-8")
    assert set(val["subject_id"]) == {456002}
    assert val["implicit_weight"].iloc[0] == pytest.approx(3.0)

    test_df = pd.read_csv(cfg.export_dir / "test_interactions.csv", encoding="utf-8")
    assert set(test_df["subject_id"]) == {456003}
    assert test_df["implicit_weight"].iloc[0] == pytest.approx(4.0 * 1.3)

    # The future items never appear in train (no future leak).
    assert set(train["subject_id"]).isdisjoint({456002, 456003})

    # ---- report split/class statistics
    assert report["splits"]["train"]["interactions"] == 2
    assert report["splits"]["validation"]["interactions"] == 1
    assert report["splits"]["test"]["interactions"] == 1
    assert report["unassigned_items"] == 3  # no date + beyond window + missing metadata
    assert report["item_classes"]["warm_item"] == 2
    assert report["item_classes"]["few_shot_item"] == 2
    assert report["item_classes"]["cold_item"] == 2
    assert report["item_classes"]["new_release"] == 2

    # ---- subjects.csv: pandas-readable with the expected columns
    subj = pd.read_csv(cfg.export_dir / "subjects.csv", encoding="utf-8")
    assert len(subj) == 5
    for col in ("subject_id", "name", "name_cn", "air_date", "year", "season",
                "platform", "tags", "meta_tags", "score", "rank", "image_url"):
        assert col in subj.columns, col

    # ---- item_features.jsonl: complete feature records
    lines = (cfg.export_dir / "item_features.jsonl").read_text(encoding="utf-8").strip().splitlines()
    assert len(lines) == 5
    records = [json.loads(line) for line in lines]
    for key in ("subject_id", "name", "name_cn", "air_date", "year", "season",
                "season_name", "platform", "episode_count", "summary", "tags",
                "meta_tags", "infobox", "score", "rank", "rating_total",
                "collection_total", "wish_count", "doing_count", "collect_count",
                "on_hold_count", "dropped_count", "image_url", "production",
                "director", "series_composer", "original_work", "music",
                "voice_actors", "related", "related_prequel_sequel",
                "air_date_window", "flags"):
        assert key in records[0], key
    by_id = {r["subject_id"]: r for r in records}
    assert by_id[456001]["production"] == ["示例公司"]
    assert by_id[456001]["related_prequel_sequel"][0]["id"] == 990001
    assert by_id[456001]["air_date_window"] == "train"
    assert by_id[456001]["flags"] == ["warm_item", "few_shot_item"]
    assert by_id[456004]["air_date_window"] is None
    assert by_id[456004]["flags"] == ["unknown_air_date"]
    assert by_id[456004]["tags"] == []

    # ---- coverage
    assert report["coverage"]["name"] == 1.0
    assert report["coverage"]["air_date"] == pytest.approx(0.8)
    assert report["coverage"]["tags"] == pytest.approx(0.8)
    assert report["coverage"]["infobox"] == pytest.approx(0.8)
    assert report["coverage"]["related"] == 1.0

    # ---- temporal quality / leakage / readiness
    assert report["temporal_quality"]["updated_at_coverage"] == 1.0
    assert report["temporal_quality"]["unassigned_interactions"] == 0
    assert report["temporal_quality"]["future_interactions"] == 0
    assert report["temporal_quality"]["invalid_temporal_interactions"] == 0
    assert report["temporal_quality"]["train_interactions_after_cutoff"] == 0
    assert report["evaluation"]["strict_temporal"] is True
    assert report["evaluation"]["potential_feature_leakage"] is False
    assert report["interactions"]["subject_reference_coverage"] == pytest.approx(0.8)
    assert report["interactions"]["missing_distinct_subjects"] == 1
    assert report["item_classes"]["strict_cold_new_release"] == 2
    assert report["readiness"]["ready_for_content_baseline"] is True
    assert report["readiness"]["ready_for_als"] is False
    assert "als_blockers" in report["readiness"]
    assert report["readiness"]["cold_validation_items"] == 1
    assert report["readiness"]["cold_test_items"] == 1

    # ---- fetch / seed users / duplicates
    assert report["fetch"]["failed_request_log_entries"] == 0
    assert report["seed_users"]["requested"] == 0
    assert report["duplicates"]["interactions_updated"] == 0


def test_train_after_cutoff_counter_detects_leakage():
    """Train rows whose updated_at is after the cutoff (or unparseable) are
    temporal leakage; the counter must recompute from raw timestamps instead
    of trusting the split label/reason pair."""
    frame = pd.DataFrame([
        {"split": "train", "split_reason": "ok", "updated_at": "2026-01-15T00:00:00Z"},
        {"split": "train", "split_reason": "ok", "updated_at": "2025-06-01T00:00:00Z"},
        {"split": "train", "split_reason": "ok", "updated_at": None},
        {"split": "validation", "split_reason": "ok", "updated_at": "2026-02-01T00:00:00Z"},
    ])
    assert export._count_train_after_cutoff(frame, dt.date(2025, 12, 31)) == 2


def test_export_temporal_edge_cases(tmp_path, store):
    """unassigned / future / invalid_temporal rows never enter split files."""
    store.upsert_subject(_subject(456010, "训练条目", "2025-03-01"))
    store.upsert_subject(_subject(456011, "验证条目", "2026-01-15"))
    store.mark_subject_status(456010, "ok")
    store.mark_subject_status(456011, "ok")

    store.upsert_interaction(_interaction("u" * 64, 456010, weights.COLLECTION_TYPE_ID["wish"], 7,
                                          updated="2025-06-01T00:00:00+08:00"))  # train
    # future: after the test window
    store.upsert_interaction(_interaction("v" * 64, 456010, weights.COLLECTION_TYPE_ID["wish"], 7,
                                          updated="2026-08-01T00:00:00Z"))
    # invalid temporal: updated_at before the item aired
    store.upsert_interaction(_interaction("w" * 64, 456011, weights.COLLECTION_TYPE_ID["doing"], 0,
                                          updated="2025-06-01T00:00:00Z"))  # air 2026-01-15
    # missing updated_at
    store.upsert_interaction(_interaction("x" * 64, 456011, weights.COLLECTION_TYPE_ID["doing"], 0,
                                          updated=None))

    cfg = _cfg(tmp_path)
    report = export.build_export(store, cfg)
    assert report["temporal_quality"]["unassigned_interactions"] == 1
    assert report["temporal_quality"]["future_interactions"] == 1
    assert report["temporal_quality"]["invalid_temporal_interactions"] == 1

    train = pd.read_csv(cfg.export_dir / "train_interactions.csv", encoding="utf-8")
    assert set(train["subject_id"]) == {456010}
    assert len(train) == 1  # the future row must not leak into train
    master = pd.read_csv(cfg.export_dir / "interactions.csv", encoding="utf-8")
    assert len(master) == 4  # all rows present in master with their split labels
    assert set(master["split"]) == {"train", "unassigned", "future", "invalid_temporal"}


def test_item_features_jsonl_is_strict_json_with_null_not_nan(tmp_path, store):
    """A NULL score/rank column becomes float64 NaN in the DataFrame; the
    jsonl must stay strict JSON (jq/JSON.parse compatible) with null instead."""
    scored = _subject(456201, "有评分", "2025-03-01")
    scored["score"] = 8.1
    store.upsert_subject(scored)
    store.upsert_subject(_subject(456202, "无评分", "2025-04-01"))
    store.mark_subject_status(456201, "ok")
    store.mark_subject_status(456202, "ok")

    cfg = _cfg(tmp_path)
    export.build_export(store, cfg)

    def _reject_constant(token):
        raise ValueError(f"non-standard JSON constant: {token}")

    lines = (cfg.export_dir / "item_features.jsonl").read_text(
        encoding="utf-8"
    ).strip().splitlines()
    records = [json.loads(line, parse_constant=_reject_constant) for line in lines]
    by_id = {record["subject_id"]: record for record in records}
    assert by_id[456201]["score"] == 8.1
    assert by_id[456202]["score"] is None


def test_export_empty_store(tmp_path, store):
    cfg = _cfg(tmp_path)
    report = export.build_export(store, cfg)
    assert report["subjects"]["total"] == 0
    assert report["interactions"]["total"] == 0
    assert report["interactions"]["sparsity"] == 1.0
    assert report["splits"]["train"]["interactions"] == 0
    for name in ("subjects.csv", "interactions.csv", "train_interactions.csv",
                 "validation_interactions.csv", "test_interactions.csv",
                 "item_features.jsonl", "dataset_report.json"):
        assert (cfg.export_dir / name).exists(), name
    master = pd.read_csv(cfg.export_dir / "interactions.csv", encoding="utf-8")
    assert list(master.columns) == export.INTERACTION_MASTER_COLUMNS
    assert len(master) == 0


def test_complete_only_and_clean_model_views(tmp_path, store):
    for sid in (456101, 456102, 456103):
        store.upsert_subject(_subject(sid, f"条目{sid}", "2025-03-01"))
        store.mark_subject_status(sid, "ok")

    complete_id = "c" * 64
    incomplete_id = "i" * 64
    store.set_seed_user(
        "local-complete",
        complete_id,
        "complete",
        2,
        is_complete=True,
        stop_reason="end_of_stream",
    )
    store.set_seed_user(
        "local-incomplete",
        incomplete_id,
        "truncated",
        1,
        is_complete=False,
        stop_reason="run_page_limit",
    )
    store.upsert_interaction(_interaction(
        complete_id, 456101, weights.COLLECTION_TYPE_ID["collect"], 8
    ))
    store.upsert_interaction(_interaction(
        complete_id, 456102, weights.COLLECTION_TYPE_ID["doing"], 0
    ))
    store.upsert_interaction(_interaction(
        incomplete_id, 456103, weights.COLLECTION_TYPE_ID["collect"], 9
    ))

    cfg = DatasetConfig(
        interactions={
            "complete_only": True,
            "min_positive_interactions": 2,
            "core_min_item_support": 1,
        },
        splits={"train_end_date": "2025-12-31"},
        output={"data_dir": "data"},
    )
    cfg.set_base_dir(tmp_path)
    report = export.build_export(store, cfg)

    master = pd.read_csv(cfg.export_dir / "interactions.csv")
    assert len(master) == 3  # evidence is retained, even if not model eligible
    assert master["collection_complete"].sum() == 2
    train = pd.read_csv(cfg.export_dir / "train_interactions.csv")
    assert set(train["anon_user_id"]) == {complete_id}
    assert set(train["subject_id"]) == {456101, 456102}
    assert set(pd.read_csv(cfg.export_dir / "train_strong_interactions.csv")["subject_id"]) == {456101}
    assert set(pd.read_csv(cfg.export_dir / "train_regular_interactions.csv")["subject_id"]) == {456101, 456102}
    assert set(pd.read_csv(cfg.export_dir / "train_core_interactions.csv")["subject_id"]) == {456101, 456102}
    assert report["interactions"]["training_eligible"] == 2
    assert report["model_views"]["core"]["qualified_users"] == 1
    assert report["seed_users"]["collection_complete"] == 1
