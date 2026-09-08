from pathlib import Path
import sys
import numpy as np
import pytest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hybrid import TagEvidence, eligible, parse_query, planned_ranking, rrf, topic_matches


def record(sid=1,**values):
    return {"subject_id":sid,"name":f"作品{sid}","name_cn":"","year":2010,"episodes":12,
            "tags":["游戏改","GAL改","恋爱","搞笑"],"meta_tags":["游戏改"],
            "platform":"OVA","score":8.1,"rating_total":200,"air_date":"2010-03-01",**values}


def test_rrf_combines_evidence_instead_of_score_scales():
    a,b=np.array([4.,3,2]),np.array([.1,.3,.2])
    ids=np.array([1,2,3])
    scores=rrf([a,b],ids)
    assert scores.argmax()==1
    assert np.allclose(scores,rrf([a*1000,b*0.01],ids))
    assert np.all(rrf([np.zeros(3)],ids)==0)
    assert rrf([a],ids,window=1).tolist()==pytest.approx([1/61,0,0])
    assert rrf([np.ones(3)],ids).tolist()==pytest.approx([1/61]*3)


def test_rrf_rejects_invalid_inputs():
    with pytest.raises(ValueError): rrf([np.array([np.nan])],np.array([1]))
    with pytest.raises(ValueError): rrf([np.ones(2)],np.array([1,1]))
    with pytest.raises(ValueError): rrf([np.ones(2)],np.array([1,2]),window=0)


def test_real_user_galgame_query_has_inclusive_year_range_and_no_niche_threshold():
    p=parse_query("我想看2007-2011年小众的galgame的OVA")
    assert (p.filters.min_year,p.filters.max_year,p.filters.platform)==(2007,2011,"OVA")
    assert p.required_topics==("galgame改编",) and p.order=="niche"
    assert eligible(p,record(year=2007)) and eligible(p,record(year=2011))
    assert not eligible(p,record(year=2012))
    assert not eligible(p,record(platform="TV",tags=["OVA","游戏改","GAL改"]))
    assert not topic_matches("galgame改编",record(tags=["galgame"],meta_tags=["漫画改"]))


def test_real_user_earliest_is_date_order_not_semantic_order():
    p=parse_query("我想看最早的百合番剧")
    rows=[record(1,air_date="2000-01-01",tags=["百合"]),record(2,air_date="1990-01-01",tags=["百合"])]
    assert planned_ranking(p,np.array([1.,.1]),rows)==[1,0]
    assert any("不能证明" in note for note in p.notes)


def test_rating_strictness_and_unreleased_items():
    p=parse_query("我想找找评分大于8.0的恋爱喜剧")
    assert p.rating_min==8 and p.rating_exclusive
    assert not eligible(p,record(score=8.0))
    assert eligible(p,record(score=8.1))
    assert not eligible(p,record(tags=["恋爱"]))
    assert not eligible(p,record(air_date="2027-01-01"),as_of="2026-09-08")
    assert not eligible(p,record(air_date=""),as_of="2026-09-08")
    assert eligible(parse_query("评分不低于8.0的恋爱喜剧"),record(score=8.0))


@pytest.mark.parametrize("text,years,episodes",[
    ("2010年及以后的番，最多十二集",(2010,None),12),
    ("2010年之后的番，少于十三集",(2011,None),12),
    ("2011年以前，十二集以内",(None,2010),12),
    ("2007年至2011年，至多24话",(2007,2011),24),
])
def test_supported_numeric_phrasings(text,years,episodes):
    p=parse_query(text)
    assert (p.filters.min_year,p.filters.max_year)==years
    assert p.filters.max_episodes==episodes


def test_unknown_soft_and_negative_requirements_remain_visible():
    soft=parse_query("校园日常，最好12集以内")
    assert soft.filters.max_episodes is None and soft.unresolved
    negative=parse_query("想看日常，不要致郁和悲剧")
    assert set(negative.filters.exclude_tags)=={"致郁","悲剧"}
    assert "致郁" not in negative.semantic_text and negative.unresolved
    assert eligible(negative,record(tags=["日常"])) # Not a promise of no tragedy.
    assert not eligible(negative,record(tags=["日常","悲剧"]))
    unknown=parse_query("至少三十集的作品")
    assert unknown.unresolved


def test_invalid_contradictory_constraints_do_not_silently_relax():
    for text in ("2011-2007年的番","评分大于11的恋爱喜剧","不到1集的作品"):
        with pytest.raises(ValueError):parse_query(text)


def test_filters_precede_title_deduplication():
    p=parse_query("评分大于8.0的恋爱喜剧")
    rows=[record(1,name="同名",score=7),record(2,name="同名",score=9)]
    assert planned_ranking(p,np.array([1.,.1]),rows)==[1]


def test_niche_is_relative_votes_and_unknown_votes_do_not_win():
    p=parse_query("冷门的OVA")
    rows=[record(1,rating_total=100),record(2,rating_total=10),record(3,rating_total=0)]
    assert planned_ranking(p,np.array([3.,2.,1.]),rows)==[1,0,2]


def test_tags_are_corpus_derived_and_do_not_invent_missing_evidence():
    rows=[record(1,tags=["乐队","2024年"]),record(2,tags=["乐队"]),record(3,tags=["其他"])]
    index=TagEvidence(rows)
    values=index.score("想看乐队")
    assert values[0]==values[1]>values[2]
    assert index.score("没有出现的标签").sum()==0
