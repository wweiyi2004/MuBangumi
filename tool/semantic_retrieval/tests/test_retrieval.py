import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from download_model import verify
from retrieval import (Filters, app_rule_scores, declared_episodes, known_positive_metrics,
                       normalize, prepare_corpus, quantize_vectors, ranked_indices)
from run import cached_embeddings, load_queries
from search import load_bundle


def record(sid=1, **extra):
    return {"subject_id": sid, "name": f"作品{sid}", "name_cn": "", "year": 2022,
            "episodes": 12, "tags": ["日常"], "summary": "", "platform": "TV",
            "score": 0, "rank": 0, "rating_total": 0, **extra}


@pytest.mark.parametrize("value,expected", [(["12"], 12), (["全12集"], 12), (["１２話"], None),
    (["12话"], 12), (["12", "12"], 12), (["12", "13"], None), (["12+OVA"], None),
    (["未定"], None), ([], None), (["0"], None), (["-1"], None)])
def test_episode_counts_are_not_guessed(value, expected):
    assert declared_episodes({"episode_count": 16, "infobox": {"话数": value}}) == expected


def test_corpus_uses_main_count_and_discards_private_or_dynamic_embedding_fields(tmp_path):
    row = {"subject_id": 1, "name": "sample", "summary": "  peaceful\n school ", "tags": ["日常"],
           "meta_tags": ["TV"], "year": float("nan"), "episode_count": 16,
           "infobox": {"话数": ["12"]}, "score": 9.9, "access_token": "SECRET"}
    path = tmp_path / "items.jsonl"
    path.write_text(json.dumps(row), encoding="utf-8")
    rows, report = prepare_corpus(path)
    assert rows[0]["episodes"] == 12 and rows[0]["year"] is None
    assert rows[0]["summary"] == "peaceful school"
    assert "9.9" not in rows[0]["text"] and "SECRET" not in json.dumps(rows)
    assert report["episode_count_differs_from_export"] == 1
    path.write_text(json.dumps(row) + "\n" + json.dumps(row), encoding="utf-8")
    with pytest.raises(ValueError, match="duplicate"):
        prepare_corpus(path)


def test_hard_numeric_constraints_fail_unknown_and_use_inclusive_boundaries():
    f = Filters(min_year=2022, max_year=2022, max_episodes=12)
    assert f.permits(record())
    for r in [record(year=None), record(episodes=None), record(year=2021), record(episodes=13)]:
        assert not f.permits(r)


def test_exclusions_preserve_unknown_semantics_and_filter_ids():
    f = Filters(exclude_tags=("恋爱",), exclude_ids=(2,))
    assert f.permits(record())  # Only means not tagged; no semantic absence claim.
    assert not f.permits(record(tags=["恋爱"]))
    assert not f.permits(record(2))
    assert not Filters(platform="剧场版").permits(record())
    with pytest.raises(ValueError):
        Filters(min_year=2023, max_year=2022)
    with pytest.raises(ValueError):
        Filters(max_episodes=-1)


def test_ranking_filters_before_limit_deduplicates_and_ties_by_id():
    rows = [record(3), record(2, name="作品1"), record(1), record(4, episodes=None)]
    assert ranked_indices(np.array([1, 1, 1, 2]), rows, Filters(max_episodes=12)) == [2, 0]
    assert ranked_indices(np.ones(4), rows, Filters(exclude_ids=(1, 2, 3, 4))) == []
    with pytest.raises(ValueError):
        ranked_indices(np.array([float("nan")] * 4), rows)


def test_vector_quantization_preserves_directions_not_just_dimensions():
    values = normalize(np.random.default_rng(19).normal(size=(24, 512)))
    q, scales = quantize_vectors(values)
    restored = normalize(q.astype(np.float32) * scales[:, None])
    assert q.dtype == np.int8 and scales.dtype == np.dtype("<f4")
    assert np.min(np.sum(values * restored, axis=1)) > 0.9999
    assert np.argmax(restored @ values.T, axis=1).tolist() == list(range(24))
    with pytest.raises(ValueError):
        normalize(np.zeros((1, 512)))
    with pytest.raises(ValueError):
        normalize(np.array([[float("nan")]]))


def test_metric_uses_ranked_known_positives_and_does_not_invent_precision():
    result = known_positive_metrics([[7, 1], [9]], [{"relevant_subject_ids": [1, 2]}, {"relevant_subject_ids": [3]}])
    assert result["known_positive_hit@1"] == 0
    assert result["known_positive_hit@5"] == 0.5
    assert result["known_positive_mrr@10"] == 0.25
    assert not any("precision" in key for key in result)


def test_rule_components_match_the_empty_taste_app_formula():
    r = record(tags=["日常", "职场"], name="职场", summary="日常", score=8, rank=100, rating_total=1000)
    # Two tag matches, two keyword fragments, public score/rank/count.
    assert app_rule_scores("日常 职场", [r])[0] == pytest.approx(64 + 2900 / 300 + 2.5 + 28 + 12)


def test_query_labels_must_exist_and_pass_conditions(tmp_path):
    path = tmp_path / "queries.json"
    path.write_text(json.dumps({"queries": [{"id":"a", "text":"x", "relevant_subject_ids":[1], "filters":{"max_episodes":11}}]}))
    with pytest.raises(ValueError, match="ineligible"):
        load_queries(path, [record()])


def test_download_hash_detects_same_size_corruption(tmp_path):
    path = tmp_path / "file"
    path.write_bytes(b"abc")
    assert verify(path, {"size":3, "sha256": hashlib.sha256(b"abc").hexdigest()})
    assert not verify(path, {"size":3, "sha256": hashlib.sha256(b"xyz").hexdigest()})
    assert verify(path, {"size":3, "git_blob": hashlib.sha1(b"blob 3\0abc").hexdigest()})


def test_bundle_integrity_failure_precedes_model_loading(tmp_path):
    files = {n: {"bytes":0,"sha256":"bad"} for n in ["vectors.i8", "scales.f32", "subject_ids.u32", "catalog.json", "onnx/model_int8.onnx", "tokenizer.json"]}
    (tmp_path / "manifest.json").write_text(json.dumps({"schema":1,"dimensions":512,"rows":1,"files":files}))
    with pytest.raises(ValueError, match="bundle path"):
        load_bundle(tmp_path)


def make_test_bundle(path, *, ids=(1, 2), scales=(0.01, 0.02), wrong_model_pair=False):
    payloads = {"vectors.i8": np.ones((2, 512), dtype=np.int8).tobytes(),
                "scales.f32": np.array(scales, dtype="<f4").tobytes(),
                "subject_ids.u32": np.array(ids, dtype="<u4").tobytes(),
                "catalog.json": json.dumps([record(1), record(2)]).encode(),
                "onnx/model_int8.onnx": b"fixture-model-not-loaded",
                "tokenizer.json": b"fixture-tokenizer-not-loaded"}
    files = {}
    for name, data in payloads.items():
        target = path / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        files[name] = {"bytes":len(data), "sha256":hashlib.sha256(data).hexdigest()}
    meta = {"schema":1,"dimensions":512,"rows":2,"files":files,
            "encoder":{"model_sha256": "wrong" if wrong_model_pair else files["onnx/model_int8.onnx"]["sha256"],
                       "tokenizer_sha256":files["tokenizer.json"]["sha256"]}}
    (path / "manifest.json").write_text(json.dumps(meta))


def test_valid_bundle_roundtrip_keeps_ids_and_unit_vectors(tmp_path):
    make_test_bundle(tmp_path)
    _, rows, vectors = load_bundle(tmp_path)
    assert [r["subject_id"] for r in rows] == [1, 2]
    assert vectors.shape == (2, 512)
    assert np.allclose(np.linalg.norm(vectors, axis=1), 1)


@pytest.mark.parametrize("kwargs,reason", [({"ids":(2,1)}, "order"),
    ({"ids":(1,1)}, "order"), ({"scales":(float('nan'),0.1)}, "scales"),
    ({"wrong_model_pair":True}, "mismatch")])
def test_bundle_rejects_structural_errors_even_with_matching_file_hashes(tmp_path, kwargs, reason):
    make_test_bundle(tmp_path, **kwargs)
    with pytest.raises(ValueError, match=reason):
        load_bundle(tmp_path)


def test_bundle_rejects_tampered_vectors(tmp_path):
    make_test_bundle(tmp_path)
    (tmp_path / "vectors.i8").write_bytes(bytes(1024))
    with pytest.raises(ValueError, match="verification failed"):
        load_bundle(tmp_path)


def test_synopsis_profile_changes_only_embedding_text(tmp_path):
    row = {"subject_id":1,"name":"Sample","name_cn":"示例","summary":"中文简介。[简介原文]別の文章",
           "tags":["日常","某位声优"],"infobox":{"别名":["Alias"]}}
    path = tmp_path / "source.jsonl"
    path.write_text(json.dumps(row), encoding="utf-8")
    rich, _ = prepare_corpus(path)
    compact, _ = prepare_corpus(path, "synopsis")
    assert "某位声优" in rich[0]["text"] and "Alias" in rich[0]["text"]
    assert compact[0]["text"] == "示例\n中文简介。\n日常"
    assert {k:v for k,v in rich[0].items() if k != 'text'} == {k:v for k,v in compact[0].items() if k != 'text'}


def test_cache_invalidates_on_model_text_and_file_changes(tmp_path):
    class FakeEncoder:
        fingerprint = {"variant":"fixture","model_sha256":"first"}
        calls = 0
        def encode(self, texts, **kwargs):
            self.calls += 1
            return normalize(np.ones((len(texts), 512)))
    encoder = FakeEncoder()
    rows = [{"subject_id":1,"text":"first text"}]
    cached_embeddings(tmp_path, encoder, rows)
    cached_embeddings(tmp_path, encoder, rows)
    assert encoder.calls == 1
    encoder.fingerprint = {"variant":"fixture","model_sha256":"second"}
    cached_embeddings(tmp_path, encoder, rows)
    assert encoder.calls == 2
    rows[0]["text"] = "changed text"
    cached_embeddings(tmp_path, encoder, rows)
    assert encoder.calls == 3
    (tmp_path / "embeddings_fixture.npy").write_bytes(b"corrupt")
    cached_embeddings(tmp_path, encoder, rows)
    assert encoder.calls == 4
