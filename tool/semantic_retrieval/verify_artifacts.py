"""Check real model/index round-trip and optional actual Dart score parity."""
import argparse
import json
from pathlib import Path

import numpy as np

from download_model import DEFAULT_DATA, HERE
from retrieval import Encoder, app_rule_scores, digest, read_jsonl, write_json
from search import load_bundle


def verify_artifacts(data: Path, dart_reference: Path | None) -> dict:
    meta, catalog, vectors = load_bundle(data / "bundle")
    original = np.load(data / "embeddings_int8.npy", allow_pickle=False)
    cosine = np.sum(original * vectors, axis=1)
    q = np.fromfile(data / "bundle/vectors.i8", dtype=np.int8).reshape(original.shape)
    scales = np.fromfile(data / "bundle/scales.f32", dtype="<f4")
    raw = q.astype(np.float32) * scales[:, None]
    # For rounding-to-nearest, every coordinate must stay within half a step.
    # Peaked BGE embeddings have larger steps than Gaussian test vectors, so
    # use the quantizer's actual error bound rather than an arbitrary cosine.
    maximum_steps = float(np.max(np.abs(raw - original) / scales[:, None]))
    assert maximum_steps <= 0.5001, "Invalid quantization round-trip"
    error_bound = np.sqrt(original.shape[1]) * scales / 2
    cosine_lower_bound = 1 - 2 * error_bound**2 / (1 - error_bound)**2
    assert np.all(cosine >= cosine_lower_bound - 1e-6)
    encoder = Encoder(data / "bundle", max_length=meta["encoder"]["max_length"])
    texts = ["不善交际的女孩通过吉他和乐队认识伙伴", "四处旅行，遇见不同的人和奇异的生命，帮助他们解决生活中的难题"]
    individual = encoder.encode(texts, query=True, batch_size=1)
    batched = encoder.encode(texts, query=True, batch_size=2)
    batch_cosine = np.sum(individual * batched, axis=1)
    assert float(np.min(batch_cosine)) > 0.99, "Unexpected INT8 padding/batching instability"
    assert np.allclose(np.linalg.norm(individual, axis=1), 1, atol=1e-5)
    result = {
        "verified_bundle_rows": len(catalog), "min_catalog_roundtrip_cosine": float(np.min(cosine)),
        "maximum_coordinate_error_in_quantization_steps": maximum_steps,
        "int8_single_vs_batch_min_cosine": float(np.min(batch_cosine)),
        "offline_runtime": "onnxruntime CPUExecutionProvider", "training_performed": False,
        "bundle_manifest_sha256": digest(data / "bundle/manifest.json"),
    }
    if dart_reference:
        expected = json.loads(dart_reference.read_text(encoding="utf-8"))
        records = read_jsonl(data / "corpus.jsonl")
        spec = json.loads((HERE / "evaluation_queries.json").read_text(encoding="utf-8"))
        errors = []
        for query in spec["queries"]:
            actual = app_rule_scores(query.get("retrieval_text", query["text"]), records)
            errors.append(np.max(np.abs(actual.astype(np.float64) - np.asarray(expected[query["id"]]))))
        maximum = float(np.max(errors))
        assert maximum < 0.00002, f"Dart score parity failed: {maximum}"
        result["dart_score_parity"] = {
            "queries": len(errors), "works": len(records), "maximum_absolute_error": maximum,
            "dart_engine_sha256": digest(HERE.parent.parent / "lib/core/recommend/fan_recommend_engine.dart"),
        }
    write_json(data / "verification.json", result)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA)
    parser.add_argument("--dart-reference", type=Path)
    args = parser.parse_args()
    print(json.dumps(verify_artifacts(args.data, args.dart_reference), ensure_ascii=False, indent=2))
