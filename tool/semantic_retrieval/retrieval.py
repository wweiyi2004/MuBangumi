"""Offline semantic-search primitives, without training or user histories."""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import re
import time
import unicodedata

import numpy as np

QUERY_PREFIX = "为这个句子生成表示以用于检索相关文章："
TEXT_SCHEMA = "bangumi-content-v1"
PRESET_TAGS = "治愈 恋爱 日常 搞笑 校园 奇幻 科幻 战斗 热血 悬疑 异世界 百合 音乐 运动 致郁 萌 剧情 原创".split()


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def clean_text(value) -> str:
    if not isinstance(value, str):
        return ""
    return re.sub(r"\s+", " ", unicodedata.normalize("NFKC", value)).strip()


def positive_int(value) -> int | None:
    if isinstance(value, bool):
        return None
    try:
        n = float(value)
        return int(n) if math.isfinite(n) and n > 0 and n.is_integer() else None
    except (ValueError, TypeError):
        return None


def strings(values) -> list[str]:
    if isinstance(values, str):
        values = [values]
    if not isinstance(values, list):
        return []
    return list(dict.fromkeys(t for v in values if (t := clean_text(v))))


def declared_episodes(row: dict) -> int | None:
    # Exported episode_count can include PVs/extra chapters. Do not silently
    # use it as the number of main episodes. Ambiguous infobox values stay unknown.
    values = strings((row.get("infobox") or {}).get("话数", []))
    if not values:
        return None
    counts = []
    for value in values:
        match = re.fullmatch(r"(?:全)?\s*(\d+)\s*(?:话|集)?", value)
        if not match or not (n := positive_int(match[1])):
            return None
        counts.append(n)
    return counts[0] if len(set(counts)) == 1 else None


def prepare_corpus(source: Path, text_profile: str = "rich") -> tuple[list[dict], dict]:
    if text_profile not in ("rich", "synopsis"):
        raise ValueError("Unknown text profile")
    rows = read_jsonl(source)
    records, seen = [], set()
    changed_counts = 0
    for row in rows:
        sid = positive_int(row.get("subject_id"))
        if sid is None or sid in seen:
            raise ValueError(f"Invalid or duplicate subject ID: {sid}")
        seen.add(sid)
        tags = strings(strings(row.get("meta_tags")) + strings(row.get("tags")))
        infobox = row.get("infobox") or {}
        episodes = declared_episodes(row)
        changed_counts += int(episodes is not None and episodes != positive_int(row.get("episode_count")))
        record = {
            "subject_id": sid, "name": clean_text(row.get("name")),
            "name_cn": clean_text(row.get("name_cn")), "aliases": strings(infobox.get("别名"))[:8],
            "summary": clean_text(row.get("summary")), "tags": tags,
            "year": positive_int(row.get("year")), "episodes": episodes,
            "episode_source": "infobox.话数" if episodes is not None else "unknown",
            "platform": clean_text(row.get("platform")),
            # Retained ONLY for the reference app ranking calculation, not embedding text.
            "score": float(row.get("score") or 0), "rank": positive_int(row.get("rank")) or 0,
            "rating_total": positive_int(row.get("rating_total")) or 0,
        }
        if not math.isfinite(record["score"]):
            record["score"] = 0.0
        if not (record["name"] or record["name_cn"]):
            raise ValueError(f"Missing title: {sid}")
        # Metadata tags precede community tags; skip date/noisy long tags.
        text_tags = [t for t in tags if len(t) <= 16 and not re.match(r"^\d{4}(?:年|$)", t)][:24]
        record["text"] = "\n".join([
            "作品：" + (record["name_cn"] or record["name"]),
            "原名：" + record["name"], "别名：" + "；".join(record["aliases"][:3]),
            "题材与风格：" + "、".join(text_tags), "简介：" + record["summary"],
        ])
        if text_profile == "synopsis":
            # Deliberate diagnostic: narrative first, without names of actors,
            # studios or foreign aliases displacing the premise in the encoder.
            summary = record["summary"].split("[简介原文]", 1)[0].strip() or record["summary"]
            story_tags = [t for t in tags if t in set(PRESET_TAGS + "冒险 职场 推理 历史 美食 旅行 家庭 友情 成长 励志 喜剧".split())]
            record["text"] = "\n".join([record["name_cn"] or record["name"], summary, "、".join(story_tags)])
        records.append(record)
    records.sort(key=lambda r: r["subject_id"])
    report = {
        "source_sha256": digest(source), "text_schema": TEXT_SCHEMA, "text_profile": text_profile, "works": len(records),
        "with_summary": sum(bool(r["summary"]) for r in records),
        "known_main_episode_count": sum(r["episodes"] is not None for r in records),
        "episode_count_differs_from_export": changed_counts,
        "unknown_year": sum(r["year"] is None for r in records),
        "notes": ["Only existing public work metadata; no user interactions or credentials.",
                  "Community tags are noisy; absence of a tag does not prove absence of that theme.",
                  "Candidate catalog is a local snapshot, not all Bangumi works."],
    }
    return records, report


class Encoder:
    def __init__(self, model_dir: Path, variant: str = "int8", *, max_length: int = 384, threads: int = 4):
        import onnxruntime as ort
        from tokenizers import Tokenizer
        if not 8 <= max_length <= 512:
            raise ValueError("max_length must be between 8 and 512")
        filenames = {"int8": "model_int8.onnx", "fp32": "model.onnx"}
        self.model_path = model_dir / "onnx" / filenames[variant]
        self.tokenizer = Tokenizer.from_file(str(model_dir / "tokenizer.json"))
        self.tokenizer.enable_truncation(max_length=max_length)
        self.tokenizer.enable_padding(pad_id=0, pad_token="[PAD]")
        options = ort.SessionOptions()
        options.intra_op_num_threads = threads
        options.inter_op_num_threads = 1
        start = time.perf_counter()
        self.session = ort.InferenceSession(str(self.model_path), options, providers=["CPUExecutionProvider"])
        self.load_ms = (time.perf_counter() - start) * 1000
        self.inputs = {v.name for v in self.session.get_inputs()}
        if not self.inputs <= {"input_ids", "attention_mask", "token_type_ids"}:
            raise ValueError(f"Unexpected ONNX inputs: {self.inputs}")
        self.fingerprint = {
            "model_sha256": digest(self.model_path), "tokenizer_sha256": digest(model_dir / "tokenizer.json"),
            "max_length": max_length, "pooling": "cls_l2", "query_prefix": QUERY_PREFIX,
            "onnxruntime": ort.__version__, "variant": variant,
        }

    def encode(self, texts: list[str], *, query: bool = False, batch_size: int = 8, progress: bool = False) -> np.ndarray:
        if not texts or any(not t.strip() for t in texts):
            raise ValueError("Cannot encode empty text")
        vectors = []
        for start in range(0, len(texts), batch_size):
            batch = [(QUERY_PREFIX + t) if query else t for t in texts[start:start + batch_size]]
            encoded = self.tokenizer.encode_batch(batch)
            inputs = {
                "input_ids": np.asarray([e.ids for e in encoded], dtype=np.int64),
                "attention_mask": np.asarray([e.attention_mask for e in encoded], dtype=np.int64),
                "token_type_ids": np.asarray([e.type_ids for e in encoded], dtype=np.int64),
            }
            outputs = self.session.run(None, {k: v for k, v in inputs.items() if k in self.inputs})
            # This pinned export returns last_hidden_state, not a pooled vector.
            token_embeddings = outputs[0]
            if token_embeddings.ndim != 3 or token_embeddings.shape[2] != 512:
                raise ValueError(f"Unexpected output shape: {token_embeddings.shape}")
            vectors.append(normalize(token_embeddings[:, 0, :]))
            if progress and (start == 0 or start // batch_size % 25 == 0):
                print(f"encoded {min(start + batch_size, len(texts))}/{len(texts)}", flush=True)
        return np.concatenate(vectors)


def normalize(vectors: np.ndarray) -> np.ndarray:
    values = np.asarray(vectors, dtype=np.float32)
    if values.ndim != 2 or not np.isfinite(values).all():
        raise ValueError("Expected a finite matrix")
    norms = np.linalg.norm(values, axis=1, keepdims=True)
    if np.any(norms < 1e-12):
        raise ValueError("Zero embedding")
    return values / norms


def quantize_vectors(vectors: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    values = normalize(vectors)
    scales = np.max(np.abs(values), axis=1) / 127
    quantized = np.clip(np.rint(values / scales[:, None]), -127, 127).astype(np.int8)
    return quantized, scales.astype("<f4")


@dataclass(frozen=True)
class Filters:
    """Explicit structured constraints. No claim of general NL parsing.

    Missing year/main-episode counts fail a hard numeric constraint. Tag
    exclusions only exclude known matching community tags, not unknown themes.
    """
    min_year: int | None = None
    max_year: int | None = None
    max_episodes: int | None = None
    exclude_tags: tuple[str, ...] = ()
    exclude_ids: tuple[int, ...] = ()
    platform: str | None = None

    def __post_init__(self):
        for value in (self.min_year, self.max_year, self.max_episodes):
            if value is not None and positive_int(value) != value:
                raise ValueError("Numeric constraints must be positive integers")
        if self.min_year and self.max_year and self.min_year > self.max_year:
            raise ValueError("Invalid year range")

    def permits(self, record: dict) -> bool:
        year, episodes = record["year"], record["episodes"]
        if self.min_year is not None and (year is None or year < self.min_year):
            return False
        if self.max_year is not None and (year is None or year > self.max_year):
            return False
        if self.max_episodes is not None and (episodes is None or episodes > self.max_episodes):
            return False
        tags = {clean_text(t).casefold() for t in record["tags"]}
        return (record["subject_id"] not in self.exclude_ids
                and not any(clean_text(t).casefold() in tags for t in self.exclude_tags)
                and (self.platform is None or self.platform == record["platform"]))


def ranked_indices(scores: np.ndarray, records: list[dict], filters: Filters = Filters(), limit: int = 10) -> list[int]:
    scores = np.asarray(scores)
    if scores.shape != (len(records),) or not np.isfinite(scores).all() or limit <= 0:
        raise ValueError("Invalid scores/limit")
    # Deterministic tie-breaking; no accidental dependency on dataset row order.
    order = np.lexsort((np.array([r["subject_id"] for r in records]), -scores))
    result = []
    seen_names = set()
    for i in order:
        r = records[int(i)]
        name = re.sub(r"[\s:：\-_]", "", r["name_cn"] or r["name"]).lower()
        if not filters.permits(r) or name in seen_names:
            continue
        result.append(int(i))
        seen_names.add(name)
        if len(result) == limit:
            break
    return result


def app_rule_scores(query: str, records: list[dict]) -> np.ndarray:
    """Existing app rank components with EMPTY taste on a fixed full catalog.

    Not the live app's API candidate retrieval, minimum-score filtering, or
    personalized ranking. See the report's comparison_scope.
    """
    query = query.strip().lower()
    wanted_list = [t for t in PRESET_TAGS if t in query]
    for part in re.split(r"[\s,，、/|]+", query):
        if 2 <= len(part) <= 12 and part not in wanted_list and not re.fullmatch(r"\d{4}", part):
            wanted_list.append(part)
    wanted = set(wanted_list[:6])
    scores = []
    for r in records:
        score = max(0, r["score"]) * 8
        if 0 < r["rank"] < 3000:
            score += (3000 - r["rank"]) / 300
        score += min(r["rating_total"], 5000) / 400
        score += len(set(r["tags"]) & wanted) * 14
        blob = f"{r['name']} {r['name_cn']} {r['summary']}".lower()
        if query and query in blob:
            score += 18
        score += sum(6 for p in re.split(r"[\s,，、]+", query) if len(p) >= 2 and p in blob)
        scores.append(score)
    return np.asarray(scores, dtype=np.float32)


def lexical_scores(queries: list[str], records: list[dict]) -> np.ndarray:
    from sklearn.feature_extraction.text import TfidfVectorizer
    tfidf = TfidfVectorizer(analyzer="char", ngram_range=(1, 3), min_df=1, max_features=200000, sublinear_tf=True)
    documents = tfidf.fit_transform([r["text"] for r in records])
    return (tfidf.transform(queries) @ documents.T).toarray().astype(np.float32)


def known_positive_metrics(rankings: list[list[int]], queries: list[dict]) -> dict:
    """Incomplete positive labels: report known-positive hits, NEVER precision."""
    if len(rankings) != len(queries) or not queries:
        raise ValueError("Missing evaluation cases")
    ranks = []
    for ranking, query in zip(rankings, queries, strict=True):
        relevant = set(query["relevant_subject_ids"])
        if not relevant:
            raise ValueError("A scored case must have at least one known positive")
        ranks.append(next((i + 1 for i, sid in enumerate(ranking) if sid in relevant), None))
    return {
        "cases": len(ranks),
        **{f"known_positive_hit@{k}": sum(r is not None and r <= k for r in ranks) / len(ranks) for k in (1, 5, 10)},
        "known_positive_mrr@10": sum(1 / r for r in ranks if r is not None and r <= 10) / len(ranks),
    }
