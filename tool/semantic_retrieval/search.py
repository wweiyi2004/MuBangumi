"""Query the local prototype bundle, using ONNX Runtime CPU only."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import time

import numpy as np

from download_model import DEFAULT_DATA
from retrieval import Encoder, Filters, digest, normalize, ranked_indices


def load_bundle(bundle: Path) -> tuple[dict, list[dict], np.ndarray]:
    root = bundle.resolve()
    meta = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    if meta["schema"] != 1 or meta["dimensions"] != 512 or not 0 < meta["rows"] <= 1000000:
        raise ValueError("Unsupported bundle")
    required = {"vectors.i8", "scales.f32", "subject_ids.u32", "catalog.json", "onnx/model_int8.onnx", "tokenizer.json"}
    if not required <= set(meta["files"]):
        raise ValueError("Incomplete bundle manifest")
    for name, entry in meta["files"].items():
        path = (root / name).resolve()
        if not path.is_relative_to(root) or not path.is_file():
            raise ValueError("Invalid bundle path")
        if path.stat().st_size != entry["bytes"] or digest(path) != entry["sha256"]:
            raise ValueError(f"Bundle verification failed: {name}")
    if (meta["encoder"]["model_sha256"] != meta["files"]["onnx/model_int8.onnx"]["sha256"]
            or meta["encoder"]["tokenizer_sha256"] != meta["files"]["tokenizer.json"]["sha256"]):
        raise ValueError("Encoder and vector catalog version mismatch")
    records = json.loads((root / "catalog.json").read_text(encoding="utf-8"))
    n, dims = meta["rows"], meta["dimensions"]
    ids = np.fromfile(root / "subject_ids.u32", dtype="<u4")
    quantized = np.fromfile(root / "vectors.i8", dtype=np.int8)
    scales = np.fromfile(root / "scales.f32", dtype="<f4")
    if (len(records) != n or len(ids) != n or len(scales) != n or len(quantized) != n * dims
            or len(set(ids.tolist())) != n or np.any(ids == 0)
            or [r["subject_id"] for r in records] != ids.tolist()):
        raise ValueError("Invalid vector/ID dimensions or order")
    if not np.isfinite(scales).all() or np.any(scales <= 0):
        raise ValueError("Invalid quantization scales")
    return meta, records, normalize(quantized.reshape(n, dims).astype(np.float32) * scales[:, None])


def search(bundle: Path, query: str, filters: Filters, limit: int = 10) -> dict:
    if not query.strip():
        raise ValueError("请输入检索描述")
    start = time.perf_counter()
    meta, records, vectors = load_bundle(bundle)
    encoder = Encoder(bundle, max_length=meta["encoder"]["max_length"])
    # Check pooling/instruction too; matching dimensions alone is insufficient.
    for key in ("pooling", "query_prefix", "model_sha256", "tokenizer_sha256", "max_length"):
        if meta["encoder"][key] != encoder.fingerprint[key]:
            raise ValueError(f"Unsupported encoder/catalog pairing: {key}")
    loaded = time.perf_counter()
    values = (encoder.encode([query], query=True) @ vectors.T)[0]
    top = ranked_indices(values, records, filters, limit)
    return {
        "query": query, "offline": True, "fine_tuned": False,
        "constraint_handling": "仅执行命令行显式条件；尚未自动解析句子中的否定、年份、集数限制",
        "tag_exclusion_scope": "仅排除已标注的标签，缺失标签不保证该主题不存在",
        "load_and_verify_ms": (loaded - start) * 1000,
        "query_ms": (time.perf_counter() - loaded) * 1000,
        "results": [{"subject_id": records[i]["subject_id"], "name": records[i]["name_cn"] or records[i]["name"],
                     "similarity": float(values[i]), "year": records[i]["year"], "episodes": records[i]["episodes"],
                     "url": f"https://bgm.tv/subject/{records[i]['subject_id']}"} for i in top],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("query")
    parser.add_argument("--bundle", type=Path, default=DEFAULT_DATA / "bundle")
    parser.add_argument("--min-year", type=int)
    parser.add_argument("--max-year", type=int)
    parser.add_argument("--max-episodes", type=int)
    parser.add_argument("--exclude-tag", action="append", default=[])
    parser.add_argument("--exclude-id", type=int, action="append", default=[])
    parser.add_argument("--platform")
    parser.add_argument("--limit", type=int, default=10)
    args = parser.parse_args()
    filters = Filters(args.min_year, args.max_year, args.max_episodes, tuple(args.exclude_tag), tuple(args.exclude_id), args.platform)
    print(json.dumps(search(args.bundle, args.query, filters, args.limit), ensure_ascii=False, indent=2))
