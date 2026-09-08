"""Fixed rank fusion and a deliberately limited, inspectable Chinese query parser."""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import date
import math
import re

import numpy as np

from retrieval import Filters, clean_text, ranked_indices

# Frozen before evaluating new rankings. No learned weights or new encoder.
RRF_K = 60
RRF_WINDOW = 100
TOPICS = {
    "百合": ("百合", "gl", "girlslove"),
    "恋爱": ("恋爱", "恋愛", "爱情", "纯爱"),
    "喜剧": ("喜剧", "搞笑", "喜劇"),
    "galgame改编": ("gal改", "galgame改", "galgame改编", "gal改编", "美少女游戏改编", "视觉小说改编"),
}


def rrf(score_lists: list[np.ndarray], subject_ids: np.ndarray, *, k=RRF_K, window=RRF_WINDOW) -> np.ndarray:
    """Equal-weight reciprocal-rank fusion. Zero-evidence lists cast no votes."""
    if k <= 0 or window <= 0 or not score_lists or len(np.unique(subject_ids)) != len(subject_ids):
        raise ValueError("Invalid fusion inputs")
    result = np.zeros(len(subject_ids), dtype=np.float64)
    for scores in score_lists:
        scores = np.asarray(scores)
        if scores.shape != result.shape or not np.isfinite(scores).all():
            raise ValueError("Invalid ranking scores")
        order = np.lexsort((subject_ids, -scores))
        order = order[scores[order] > 0][:window]
        # Share a rank for equal-score evidence; arbitrary ID ties must not
        # introduce a preference except at the finite retrieval-window edge.
        previous, rank = None, 0
        for position, idx in enumerate(order, 1):
            if previous is None or scores[idx] != previous:
                rank = position
            result[idx] += 1 / (k + rank)
            previous = scores[idx]
    return result


class TagEvidence:
    """Corpus-derived short tags. No annotations or evaluation query IDs used."""
    def __init__(self, records: list[dict]):
        self.tags = [{clean_text(t).casefold() for t in r["tags"]} for r in records]
        counts = {}
        for tags in self.tags:
            for tag in tags:
                if 2 <= len(tag) <= 8 and re.search(r"[\u4e00-\u9fff]", tag) and not re.search(r"\d", tag):
                    counts[tag] = counts.get(tag, 0) + 1
        self.weights = {tag: math.log1p(len(records) / count) for tag, count in counts.items() if count >= 2}

    def score(self, query: str) -> np.ndarray:
        q = clean_text(query).casefold()
        matched = {tag: w for tag, w in self.weights.items() if tag in q}
        return np.asarray([sum(w for tag, w in matched.items() if tag in tags) for tags in self.tags])


def chinese_number(text: str) -> int:
    text = clean_text(text)
    if text.isdecimal():
        return int(text)
    digits = dict(zip("零一二三四五六七八九", range(10)))
    text = text.replace("两", "二")
    if text == "十":
        return 10
    if "十" in text:
        left, right = text.split("十", 1)
        return (digits[left] if left else 1) * 10 + (digits[right] if right else 0)
    return digits[text]


@dataclass
class QueryPlan:
    text: str
    semantic_text: str
    filters: Filters = field(default_factory=Filters)
    rating_min: float | None = None
    rating_exclusive: bool = False
    required_topics: tuple[str, ...] = ()
    order: str = "relevance"
    notes: list[str] = field(default_factory=list)
    unresolved: list[str] = field(default_factory=list)

    def to_dict(self):
        return asdict(self)


def parse_query(text: str) -> QueryPlan:
    text = clean_text(text)
    if not text:
        raise ValueError("Empty query")
    rest, fields = text, {}
    plan = QueryPlan(text, text)
    bounds = re.findall(r"(?<!\d)(\d{4})\s*(?:年\s*)?[-—–~～至到]\s*(\d{4})\s*年?", rest)
    if len(bounds) > 1:
        raise ValueError("Multiple year ranges need clarification")
    if bounds:
        fields["min_year"], fields["max_year"] = map(int, bounds[0])
        rest = re.sub(r"(?<!\d)\d{4}\s*(?:年\s*)?[-—–~～至到]\s*\d{4}\s*年?", " ", rest)
    for pattern, key, offset in [
        (r"(\d{4})年(?:及以后|起)", "min_year", 0),
        (r"(\d{4})年(?:之后|以后|后)", "min_year", 1),
        (r"(\d{4})年及以前", "max_year", 0),
        (r"(\d{4})年(?:之前|以前|前)", "max_year", -1),
    ]:
        for match in list(re.finditer(pattern, rest)):
            value = int(match[1]) + offset
            if key in fields:
                value = max(fields[key], value) if key == "min_year" else min(fields[key], value)
            fields[key] = value
        rest = re.sub(pattern, " ", rest)
    number = r"([0-9]+|[一二两三四五六七八九十]{1,3})"
    for pattern, offset in [
        (rf"(?:不超过|最多|至多){number}\s*(?:集|话)", 0),
        (rf"{number}\s*(?:集|话)(?:以内|以下|及以下)", 0),
        (rf"(?:少于|不到){number}\s*(?:集|话)", -1),
    ]:
        for match in list(re.finditer(pattern, rest)):
            preceding = re.split(r"[，,。；;]", rest[:match.start()])[-1]
            if re.search(r"最好|尽量|优先|希望", preceding[-8:]):
                plan.unresolved.append("集数为软偏好，未作为硬条件执行：" + match[0])
                continue
            value = chinese_number(match[1]) + offset
            fields["max_episodes"] = min(fields.get("max_episodes", value), value)
        rest = re.sub(pattern, " ", rest)
    ratings = list(re.finditer(r"(?:评分|分数)\s*(大于|高于|超过|不低于|至少|>=|>|≥)\s*(\d+(?:\.\d+)?)", rest))
    if len(ratings) > 1:
        raise ValueError("Multiple rating conditions need clarification")
    if ratings:
        m = ratings[0]
        plan.rating_min, plan.rating_exclusive = float(m[2]), m[1] in ("大于", "高于", "超过", ">")
        if not 0 <= plan.rating_min <= 10:
            raise ValueError("Rating must be within 0–10")
        rest = rest.replace(m[0], " ")
    exclusions = []
    for m in list(re.finditer(r"(?:不要|排除|不想看)([^，,。；;]+)", rest)):
        clause = m[1]
        for word in ("百合", "恋爱", "喜剧", "恐怖", "致郁", "悲剧", "战斗", "后宫"):
            if word in clause:
                exclusions.extend(TOPICS.get(word, (word,)))
        # No metadata here can certify that a work has NONE of a theme.
        plan.unresolved.append("否定要求仅能排除已知标签，不能保证主题不存在：" + m[0])
        rest = rest.replace(m[0], " ")
    if exclusions:
        fields["exclude_tags"] = tuple(dict.fromkeys(exclusions))
    format_matches = re.findall(r"(?i)(?<![a-z])(OVA|TV|WEB)(?![a-z])", rest)
    if len(set(m.upper() for m in format_matches)) > 1:
        plan.unresolved.append("多种播出形式暂未作为硬条件执行")
    elif format_matches:
        fields["platform"] = format_matches[0].upper()
        rest = re.sub(r"(?i)(?<![a-z])(OVA|TV|WEB)(?![a-z])", " ", rest)
    topics = []
    if re.search(r"(?i)galgame|gal改|美少女游戏改编|视觉小说改编", rest):
        topics.append("galgame改编")
        plan.notes.append("galgame 按美少女/视觉小说游戏改编动画理解；排除明确漫画改的冲突标签")
    if "百合" in rest:
        topics.append("百合")
        plan.notes.append("百合归类依据目录标签，可能包括含百合元素的作品")
    if "恋爱" in rest or "爱情" in rest:
        topics.append("恋爱")
    if "喜剧" in rest or "搞笑" in rest:
        topics.append("喜剧")
    if "最早" in rest:
        plan.order = "oldest"
        plan.notes.append("只排序当前目录中首播日期已知的作品，不能证明动画史上最早")
    elif "小众" in rest or "冷门" in rest:
        plan.order = "niche"
        plan.notes.append("小众没有客观阈值：暂按评分人数从少到多排列，不等于已认定小众")
    if re.search(r"(?:集|话|评分|分数|\d{4}年)", rest):
        plan.unresolved.append("有未识别的数值条件，需检查原句")
    plan.filters = Filters(**fields)
    plan.required_topics = tuple(topics)
    plan.semantic_text = re.sub(r"我想(?:看|找找?|要)|有没有|最早的?|小众的?|冷门的?", " ", rest).strip(" ，,。") or text
    return plan


def topic_matches(topic: str, record: dict) -> bool:
    tags = {clean_text(t).casefold() for t in record["tags"]}
    if topic == "galgame改编":
        meta = {clean_text(t).casefold() for t in record.get("meta_tags", [])}
        if "漫画改" in meta and "游戏改" not in meta:
            return False
        return (bool(tags & set(TOPICS[topic]))
                or ("游戏改" in tags and bool(tags & {"galgame", "gal", "美少女游戏", "视觉小说"})))
    return bool(tags & set(TOPICS[topic]))


def eligible(plan: QueryPlan, record: dict, *, as_of: str | None = None) -> bool:
    if not plan.filters.permits(record):
        return False
    if plan.rating_min is not None:
        rating = record.get("score", 0)
        if not rating or not math.isfinite(rating):
            return False
        too_low = rating <= plan.rating_min if plan.rating_exclusive else rating < plan.rating_min
        if too_low:
            return False
    if not all(topic_matches(t, record) for t in plan.required_topics):
        return False
    if as_of:
        try:
            if date.fromisoformat(record.get("air_date", "")) > date.fromisoformat(as_of):
                return False
        except (TypeError, ValueError):
            return False
    return True


def planned_ranking(plan: QueryPlan, scores: np.ndarray, records: list[dict], *, limit=10, as_of=None) -> list[int]:
    allowed = [i for i, record in enumerate(records) if eligible(plan, record, as_of=as_of)]
    if not allowed:
        return []
    order = [allowed[i] for i in ranked_indices(np.asarray(scores)[allowed], [records[i] for i in allowed], limit=len(allowed))]
    if plan.order == "oldest":
        order = [i for i in order if re.fullmatch(r"\d{4}-\d{2}-\d{2}", records[i].get("air_date", ""))]
        order.sort(key=lambda i: (records[i]["air_date"], -scores[i], records[i]["subject_id"]))
    elif plan.order == "niche":
        order.sort(key=lambda i: (records[i].get("rating_total", 0) or math.inf, -scores[i], records[i]["subject_id"]))
    return order[:limit]
