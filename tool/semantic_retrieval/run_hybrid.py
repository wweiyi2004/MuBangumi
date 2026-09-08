"""Compare fixed hybrid retrieval and inspect actual user requirements offline."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import time

import numpy as np

from download_model import HERE
from hybrid import RRF_K, RRF_WINDOW, TagEvidence, eligible, parse_query, planned_ranking, rrf
from retrieval import Encoder, Filters, clean_text, digest, lexical_scores, ranked_indices, read_jsonl, write_json
from run import evaluate, load_queries
from search import load_bundle


def compare_case_sets(name, spec, records, vectors, encoder, evidence):
    queries = spec["queries"]
    texts = [q.get("retrieval_text", q["text"]) for q in queries]
    lexical = lexical_scores(texts, records)
    semantic = encoder.encode(texts, query=True, batch_size=1) @ vectors.T
    tags = np.stack([evidence.score(t) for t in texts])
    ids = np.asarray([r["subject_id"] for r in records])
    fused, fused_tags = [], []
    for i, q in enumerate(queries):
        filters = Filters(**q.get("filters", {}))
        mask = np.array([filters.permits(r) for r in records])
        lists = [np.where(mask, scores[i], 0) for scores in (lexical, semantic, tags)]
        fused.append(rrf(lists[:2], ids))
        fused_tags.append(rrf(lists, ids))
    result = {"name":name,"metrics":{},"details":{}}
    for method, scores in {"char_tfidf":lexical,"bge_int8":semantic,
                           "rrf_lexical_bge":np.asarray(fused),"rrf_lexical_bge_tags":np.asarray(fused_tags)}.items():
        result["metrics"][method], result["details"][method] = evaluate(scores, queries, records)
    comparisons = {}
    primary = result["details"]["rrf_lexical_bge"]
    for baseline in ("char_tfidf", "bge_int8"):
        def hits(rows):
            return np.array([int(r["first_known_positive_rank"] is not None and r["first_known_positive_rank"] <= 5) for r in rows])
        delta = hits(primary) - hits(result["details"][baseline])
        samples = np.random.default_rng(20260908).choice(delta, size=(10000,len(delta)), replace=True).mean(axis=1)
        comparisons[baseline] = {"won_cases":int(np.sum(delta>0)),"lost_cases":int(np.sum(delta<0)),
                                 "hit5_difference":float(delta.mean()),"paired_bootstrap_95_interval":np.percentile(samples,[2.5,97.5]).tolist()}
    result["paired_comparisons"] = comparisons
    return result


def run(args):
    args.output.mkdir(parents=True, exist_ok=True)
    protocol = json.loads((HERE / "hybrid_protocol.json").read_text(encoding="utf-8"))
    assert protocol["k"] == RRF_K and protocol["window"] == RRF_WINDOW
    meta, catalog, vectors = load_bundle(args.data / "bundle")
    records = read_jsonl(args.data / "corpus.jsonl")
    if [r["subject_id"] for r in records] != [r["subject_id"] for r in catalog]:
        raise ValueError("Corpus and vector ID order differs")
    raw = {r["subject_id"]:r for r in read_jsonl(args.source)}
    source_report = json.loads((args.data / "corpus_report.json").read_text(encoding="utf-8"))
    if source_report["source_sha256"] != digest(args.source) or source_report["text_profile"] != "synopsis":
        raise ValueError("Corpus source/profile mismatch")
    # Verify corpus text against the embedding cache stamp, not only matching IDs.
    import hashlib
    text_hash = hashlib.sha256(json.dumps([(r["subject_id"],r["text"]) for r in records],ensure_ascii=False).encode()).hexdigest()
    cache = json.loads((args.data / "embeddings_int8.json").read_text(encoding="utf-8"))
    if text_hash != cache["stamp"]["text_sha256"]:
        raise ValueError("Corpus text differs from vector source")
    for record in records:
        record["air_date"] = clean_text(raw[record["subject_id"]].get("air_date"))
        record["meta_tags"] = raw[record["subject_id"]].get("meta_tags", [])
    encoder = Encoder(args.data / "bundle", max_length=meta["encoder"]["max_length"])
    for key in ("model_sha256","tokenizer_sha256","pooling","query_prefix"):
        if encoder.fingerprint[key] != meta["encoder"][key]:
            raise ValueError("Encoder pairing mismatch")
    evidence = TagEvidence(records)
    report = {"protocol":protocol,"as_of":args.as_of,"corpus_works":len(records),"trained":False,
              "provenance":{name:digest(HERE/name) for name in ("run_hybrid.py","hybrid.py","hybrid_protocol.json","evaluation_queries.json","additional_queries.json","user_queries.json")},
              "source_sha256":digest(args.source),"bundle_manifest_sha256":digest(args.data/"bundle/manifest.json"),"sets":{},"user_cases":[]}
    prior_ids = set()
    for filename, label in (("evaluation_queries.json","original_development_50"),("additional_queries.json","additional_assistant_20")):
        spec = load_queries(HERE / filename, records)
        positives = {i for q in spec["queries"] for i in q["relevant_subject_ids"]}
        if filename == "additional_queries.json" and positives & prior_ids:
            raise ValueError("New known-positive IDs overlap original cases")
        prior_ids |= positives
        report["sets"][label] = compare_case_sets(label,spec,records,vectors,encoder,evidence)
        print(label, json.dumps(report["sets"][label]["metrics"],ensure_ascii=False),flush=True)
    users = json.loads((HERE / "user_queries.json").read_text(encoding="utf-8"))["queries"]
    ids = np.asarray([r["subject_id"] for r in records])
    for query in users:
        # This is the full original sentence, without the newly implemented
        # parser or metadata filters. Keep it separate from the labeled sets.
        raw_semantic = (encoder.encode([query["text"]],query=True) @ vectors.T)[0]
        raw_order = ranked_indices(raw_semantic,records,limit=5)
        start = time.perf_counter()
        plan = parse_query(query["text"])
        lexical = lexical_scores([plan.semantic_text], records)[0]
        semantic = (encoder.encode([plan.semantic_text],query=True) @ vectors.T)[0]
        mask = np.array([eligible(plan,r,as_of=args.as_of) for r in records])
        fused = rrf([np.where(mask,lexical,0),np.where(mask,semantic,0)],ids)
        order = planned_ranking(plan,fused,records,as_of=args.as_of)
        results = [{"subject_id":records[i]["subject_id"],"name":records[i]["name_cn"]or records[i]["name"],
                    "date":records[i]["air_date"],"score":records[i]["score"],"rating_total":records[i]["rating_total"],
                    "platform":records[i]["platform"],"meta_tags":records[i]["meta_tags"],
                    "matched_topics":[t for t in plan.required_topics],"rank_fusion_score":float(fused[i])} for i in order]
        report["user_cases"].append({**query,"plan":plan.to_dict(),"eligible_count":int(mask.sum()),"results":results,
                                     "raw_bge_top5":[{"subject_id":records[i]["subject_id"],
                                                      "name":records[i]["name_cn"]or records[i]["name"],
                                                      "date":records[i]["air_date"],"score":records[i]["score"],
                                                      "platform":records[i]["platform"],
                                                      "passes_known_metadata_conditions":eligible(plan,records[i],as_of=args.as_of)} for i in raw_order],
                                     "known_hard_constraint_violations":sum(not eligible(plan,records[i],as_of=args.as_of) for i in order),
                                     "timing_includes_rebuilding_lexical_index_ms":(time.perf_counter()-start)*1000})
    write_json(args.output/"report.json",report)
    lines=["# 混合检索验证", "", "固定 RRF k=60、窗口 100、等权；没有调参或微调。指标为不完整标注下的已知正例命中，不是准确率。", ""]
    for name,result in report["sets"].items():
        lines += ["## "+name,"","| 方法 | Hit@1 | Hit@5 | Hit@10 | MRR@10 |","| --- | ---: | ---: | ---: | ---: |"]
        for method,m in result["metrics"].items():
            lines.append(f"| {method} | {m['known_positive_hit@1']:.0%} | {m['known_positive_hit@5']:.0%} | {m['known_positive_hit@10']:.0%} | {m['known_positive_mrr@10']:.4f} |")
        lines += ["",json.dumps(result["paired_comparisons"],ensure_ascii=False),""]
    for case in report["user_cases"]:
        lines += ["## 原句纯 BGE："+case["text"],"", "未经过条件解析或元数据过滤；下面的布尔值不评判小众程度或历史最早。", "", "| 作品 | 日期 | 评分 | 形式 | 满足已知元数据条件 |", "| --- | --- | ---: | --- | --- |"]
        for r in case["raw_bge_top5"]:
            lines.append(f"| [{r['name'].replace('|','/')}](https://bgm.tv/subject/{r['subject_id']}) | {r['date']} | {r['score']} | {r['platform']} | {r['passes_known_metadata_conditions']} |")
        lines.append("")
        lines += ["## "+case["text"],"",f"目录内符合已知硬条件的作品数：{case['eligible_count']}。评分是本地快照，需另行在线核对。","", "```json",json.dumps(case["plan"],ensure_ascii=False,indent=2),"```", "", "| 作品 | 日期 | 评分 | 评分人数 | 形式 |", "| --- | --- | ---: | ---: | --- |"]
        for r in case["results"]:
            lines.append(f"| [{r['name'].replace('|','/')}](https://bgm.tv/subject/{r['subject_id']}) | {r['date']} | {r['score']} | {r['rating_total']} | {r['platform']} |")
        lines.append("")
    (args.output/"report.md").write_text("\n".join(lines),encoding="utf-8")
    print(json.dumps(report["user_cases"],ensure_ascii=False,indent=2),flush=True)


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data",type=Path,default=HERE.parent/"recommend_dataset/data/semantic_bge_synopsis_v1")
    parser.add_argument("--source",type=Path,default=HERE.parent/"recommend_dataset/data/expand_v1/export_all/item_features.jsonl")
    parser.add_argument("--output",type=Path,default=HERE.parent/"recommend_dataset/data/semantic_hybrid_v1")
    parser.add_argument("--as-of",default="2026-09-08")
    run(parser.parse_args())
