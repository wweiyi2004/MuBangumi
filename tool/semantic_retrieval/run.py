"""Build and evaluate a frozen BGE baseline. Never trains or contacts a service."""
from __future__ import annotations

import argparse
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import platform
import shutil
import time

import numpy as np

from download_model import DEFAULT_DATA, HERE, verify
from retrieval import (Encoder, Filters, app_rule_scores, digest, known_positive_metrics,
                       lexical_scores, normalize, prepare_corpus, quantize_vectors,
                       ranked_indices, write_json)


def load_queries(path: Path, records: list[dict]) -> dict:
    spec = json.loads(path.read_text(encoding="utf-8"))
    by_id = {r["subject_id"]: r for r in records}
    seen = set()
    for q in spec["queries"]:
        if q["id"] in seen or not q["text"].strip() or not q["relevant_subject_ids"]:
            raise ValueError("Invalid query fixture")
        seen.add(q["id"])
        filters = Filters(**q.get("filters", {}))
        for sid in q["relevant_subject_ids"]:
            if sid not in by_id or not filters.permits(by_id[sid]):
                raise ValueError(f"Query {q['id']} has missing/ineligible positive {sid}")
    return spec


def cached_embeddings(output: Path, encoder: Encoder, records: list[dict]) -> np.ndarray:
    text_hash = hashlib.sha256(json.dumps(
        [(r["subject_id"], r["text"]) for r in records], ensure_ascii=False
    ).encode()).hexdigest()
    stamp = {"encoder": encoder.fingerprint, "text_sha256": text_hash}
    stem = "embeddings_" + encoder.fingerprint["variant"]
    matrix_file, meta_file = output / (stem + ".npy"), output / (stem + ".json")
    if matrix_file.exists() and meta_file.exists():
        meta = json.loads(meta_file.read_text(encoding="utf-8"))
        if meta.get("stamp") == stamp and meta.get("sha256") == digest(matrix_file):
            vectors = np.load(matrix_file, allow_pickle=False)
            if vectors.shape == (len(records), 512) and np.isfinite(vectors).all():
                print(f"verified cached {stem}", flush=True)
                return vectors
    vectors = encoder.encode([r["text"] for r in records], progress=True)
    np.save(matrix_file, vectors, allow_pickle=False)
    write_json(meta_file, {"stamp": stamp, "sha256": digest(matrix_file)})
    return vectors


def make_bundle(output: Path, model_dir: Path, records: list[dict], vectors: np.ndarray, encoder: Encoder) -> dict:
    bundle = output / "bundle"
    bundle.mkdir(parents=True, exist_ok=True)
    q, scales = quantize_vectors(vectors)
    q.tofile(bundle / "vectors.i8")
    scales.tofile(bundle / "scales.f32")
    np.asarray([r["subject_id"] for r in records], dtype="<u4").tofile(bundle / "subject_ids.u32")
    catalog = [{k: r[k] for k in ("subject_id", "name", "name_cn", "year", "episodes", "episode_source", "tags", "platform")} for r in records]
    (bundle / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, separators=(",", ":"), allow_nan=False), encoding="utf-8")
    (bundle / "onnx").mkdir(exist_ok=True)
    for name in ("onnx/model_int8.onnx", "tokenizer.json", "config.json", "tokenizer_config.json", "special_tokens_map.json", "source.json", "README.md"):
        shutil.copy2(model_dir / name, bundle / name)
    files = {p.relative_to(bundle).as_posix(): {"bytes": p.stat().st_size, "sha256": digest(p)}
             for p in sorted(bundle.rglob("*")) if p.is_file() and p.name != "manifest.json"}
    manifest = {
        "schema": 1, "status": "research_prototype_not_integrated_or_mobile_verified",
        "encoder": encoder.fingerprint, "rows": len(records), "dimensions": 512,
        "vector_encoding": "symmetric_per_row_int8; multiply by little-endian float32 scale then L2-normalize",
        "ids_encoding": "little-endian uint32", "files": files,
        "payload_bytes": sum(f["bytes"] for f in files.values()),
        "runtime_included": False, "license_note": "Base model MIT; upstream notices retained. Review distribution of model and work metadata before publishing.",
    }
    write_json(bundle / "manifest.json", manifest)
    manifest["total_bundle_bytes"] = sum(p.stat().st_size for p in bundle.rglob("*") if p.is_file())
    return manifest


def evaluate(scores: np.ndarray, queries: list[dict], records: list[dict]) -> tuple[dict, list[dict]]:
    rankings, details = [], []
    for q, values in zip(queries, scores, strict=True):
        filters = Filters(**q.get("filters", {}))
        order = ranked_indices(values, records, filters)
        ids = [records[i]["subject_id"] for i in order]
        rankings.append(ids)
        relevant = set(q["relevant_subject_ids"])
        details.append({
            "id": q["id"], "text": q["text"], "group": q["group"], "filters": asdict(filters),
            "known_positives": q["relevant_subject_ids"],
            "first_known_positive_rank": next((i + 1 for i, sid in enumerate(ids) if sid in relevant), None),
            "top10": [{"subject_id": records[i]["subject_id"], "name": records[i]["name_cn"] or records[i]["name"],
                       "score": float(values[i]), "year": records[i]["year"], "episodes": records[i]["episodes"]} for i in order],
        })
    by_group = {}
    for group in sorted({q["group"] for q in queries}):
        positions = [i for i, q in enumerate(queries) if q["group"] == group]
        by_group[group] = known_positive_metrics([rankings[i] for i in positions], [queries[i] for i in positions])
    return {**known_positive_metrics(rankings, queries), "by_group": by_group}, details


def render_report(report: dict, path: Path) -> None:
    lines = ["# BGE 中文番剧检索：离线开发集验证", "",
             "未微调；未接入应用；未进行手机性能验收。", "",
             "50 条需求由助手在查看模型排序前编写。正例依据本地简介和标签选取，未穷举所有相关作品，也未经过用户盲评。",
             "命中率表示找回预先列出的已知正例，不是推荐准确率或满意度。4 条条件查询的条件由人工结构化，不能据此声称已实现自然语言条件解析。", "",
             "| 方法 | 已知正例 Hit@1 | Hit@5 | Hit@10 | MRR@10 |", "| --- | ---: | ---: | ---: | ---: |"]
    for name, m in report["metrics"].items():
        lines.append(f"| {name} | {m['known_positive_hit@1']:.1%} | {m['known_positive_hit@5']:.1%} | {m['known_positive_hit@10']:.1%} | {m['known_positive_mrr@10']:.4f} |")
    lines += ["", "规则对照只重现空偏好时的本地评分，在相同完整目录上比较；不是线上 API 候选召回与完整个性化推荐的端到端对比。",
              "TF-IDF 使用相同作品文本的中文字符 1–3 gram。所有方法使用相同的显式过滤与名称去重。", "",
              "## 体积与性能", "", "```json", json.dumps(report["deployment"], ensure_ascii=False, indent=2), "```", "",
              "以上耗时为这台 Windows 电脑上的 CPU 测量，不能代表手机；文件大小不等于运行内存。", "", "## 每条需求（量化模型＋量化作品向量）", ""]
    for row in report["details"]["bge_int8_catalog_int8"]:
        lines += [f"### {row['id']} · {row['text']}", "",
                  f"已知正例首次出现：{row['first_known_positive_rank'] or '前 10 未出现'}；分组：{row['group']}。", "",
                  "| 排序 | 作品 | 相似度 |", "| --- | --- | ---: |"]
        for i, item in enumerate(row["top10"][:5], 1):
            safe_name = item["name"].replace("|", "\\|")
            lines.append(f"| {i} | [{safe_name}](https://bgm.tv/subject/{item['subject_id']}) | {item['score']:.4f} |")
        lines.append("")
    lines += ["## 尚未评分的边界查询", ""]
    for probe in report["unscored_probes"]:
        lines += [f"- {probe['text']} → " + "、".join(r["name"] for r in probe["top5"]), "  " + probe["reason"]]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run(args) -> None:
    args.output.mkdir(parents=True, exist_ok=True)
    lock = json.loads((HERE / "model.lock.json").read_text(encoding="utf-8"))
    for f in lock["files"]:
        if f["path"] == "onnx/model.onnx" and not args.reference:
            continue
        if not verify(args.model / f["path"], f):
            raise ValueError(f"Model artifact does not match lock: {f['path']}")
    records, corpus_report = prepare_corpus(args.input, args.text_profile)
    spec = load_queries(args.queries, records)
    queries = spec["queries"]
    texts = [q.get("retrieval_text", q["text"]) for q in queries]
    write_json(args.output / "corpus_report.json", corpus_report)
    # Save only the normalized public metadata used in this experiment.
    (args.output / "corpus.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False, allow_nan=False) + "\n" for r in records), encoding="utf-8")
    report = {
        "status": "offline_development_evaluation_not_product_acceptance", "trained": False,
        "dataset": corpus_report, "query_sha256": digest(args.queries), "model_lock_sha256": digest(HERE / "model.lock.json"),
        "query_policy": {k: v for k, v in spec.items() if k not in ("queries", "unscored_probes")},
        "comparison_scope": "Same fixed corpus; app local scoring only with empty taste, no API recall or user state.",
        "metrics": {}, "details": {}, "deployment": {}, "unscored_probes": [],
    }
    baseline_scores = {
        "app_rules_fixed_catalog": np.stack([app_rule_scores(t, records) for t in texts]),
        "char_tfidf": lexical_scores(texts, records),
    }
    for name, values in baseline_scores.items():
        report["metrics"][name], report["details"][name] = evaluate(values, queries, records)
    encoder = Encoder(args.model, "int8", threads=args.threads)
    vectors = cached_embeddings(args.output, encoder, records)
    query_vectors = encoder.encode(texts, query=True, batch_size=1)
    quantized, scales = quantize_vectors(vectors)
    portable_vectors = normalize(quantized.astype(np.float32) * scales[:, None])
    for name, matrix in (("bge_int8", vectors), ("bge_int8_catalog_int8", portable_vectors)):
        report["metrics"][name], report["details"][name] = evaluate(query_vectors @ matrix.T, queries, records)
    bundle = make_bundle(args.output, args.model, records, vectors, encoder)
    timings = []
    for text in texts:
        start = time.perf_counter()
        q = encoder.encode([text], query=True)
        ranked_indices((q @ portable_vectors.T)[0], records)
        timings.append((time.perf_counter() - start) * 1000)
    report["deployment"] = {
        "model_bytes": encoder.model_path.stat().st_size, "tokenizer_bytes": (args.model / "tokenizer.json").stat().st_size,
        "vector_payload_bytes": int(quantized.nbytes + scales.nbytes + len(records) * 4),
        "bundle_bytes": bundle["total_bundle_bytes"], "runtime_included": False,
        "model_load_ms": encoder.load_ms, "warm_query_samples": len(timings),
        "warm_query_p50_ms": float(np.percentile(timings, 50)), "warm_query_p95_ms": float(np.percentile(timings, 95)),
        "query_timing_scope": "tokenization + encoding + vector scan + name dedup; no network or UI",
        "hardware": platform.processor(), "platform": platform.platform(), "cpu_threads": args.threads,
        "phone_measured": False, "peak_ram_measured": False, "original_10mb_budget_met": bundle["total_bundle_bytes"] <= 10000000,
    }
    for probe in spec.get("unscored_probes", []):
        values = (encoder.encode([probe["text"]], query=True) @ portable_vectors.T)[0]
        top = ranked_indices(values, records, limit=5)
        report["unscored_probes"].append({**probe, "top5": [{"subject_id": records[i]["subject_id"], "name": records[i]["name_cn"] or records[i]["name"]} for i in top]})
    if args.reference:
        reference = Encoder(args.model, "fp32", threads=args.threads)
        reference_vectors = cached_embeddings(args.output, reference, records)
        reference_queries = reference.encode(texts, query=True, batch_size=1)
        report["metrics"]["bge_fp32"], report["details"]["bge_fp32"] = evaluate(reference_queries @ reference_vectors.T, queries, records)
        overlaps = []
        for a, b in zip(report["details"]["bge_fp32"], report["details"]["bge_int8_catalog_int8"], strict=True):
            ids_a, ids_b = ({r["subject_id"] for r in row["top10"]} for row in (a, b))
            overlaps.append(len(ids_a & ids_b) / max(1, len(ids_a)))
        report["quantization"] = {
            "query_cosine_mean": float(np.mean(np.sum(query_vectors * reference_queries, axis=1))),
            "document_cosine_mean": float(np.mean(np.sum(vectors * reference_vectors, axis=1))),
            "top10_overlap_mean": float(np.mean(overlaps)),
            "catalog_cosine_mean": float(np.mean(np.sum(vectors * portable_vectors, axis=1))),
        }
    write_json(args.output / "report.json", report)
    render_report(report, args.output / "report.md")
    print(json.dumps({"metrics": report["metrics"], "deployment": report["deployment"], "quantization": report.get("quantization")}, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=HERE.parent / "recommend_dataset/data/expand_v1/export_all/item_features.jsonl")
    parser.add_argument("--output", type=Path, default=DEFAULT_DATA)
    parser.add_argument("--model", type=Path, default=DEFAULT_DATA / "model")
    parser.add_argument("--queries", type=Path, default=HERE / "evaluation_queries.json")
    parser.add_argument("--reference", action="store_true")
    parser.add_argument("--text-profile", choices=("rich", "synopsis"), default="rich")
    parser.add_argument("--threads", type=int, default=4)
    run(parser.parse_args())
