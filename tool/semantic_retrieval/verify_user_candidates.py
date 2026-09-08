"""Read-only live Bangumi metadata check for the three user's result lists.

At most 15 public requests, one at a time. Stop on auth/rate-limit challenges.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import time
import urllib.error
import urllib.request

from download_model import HERE
from retrieval import write_json


def run(data):
    report = json.loads((data / "report.json").read_text(encoding="utf-8"))
    ids = list(dict.fromkeys(r["subject_id"] for case in report["user_cases"] for r in case["results"][:5]))[:15]
    out = {"checked_at_utc":datetime.now(timezone.utc).isoformat(),"source":"https://api.bgm.tv/v0/subjects/{id}",
           "snapshots":{},"errors":[],"note":"No new candidate discovery; checks only the displayed local candidates."}
    for index, sid in enumerate(ids):
        if index:
            time.sleep(1.1)
        request = urllib.request.Request(f"https://api.bgm.tv/v0/subjects/{sid}",headers={
            "User-Agent":"MuBangumi/2.2.0 (local retrieval evaluation; https://github.com/wweiyi2004/MuBangumi)",
            "Accept":"application/json"})
        try:
            with urllib.request.urlopen(request,timeout=20) as response:
                body = response.read(2*1024*1024+1)
                if len(body)>2*1024*1024:
                    raise ValueError("Unexpected response size")
                row=json.loads(body)
            out["snapshots"][str(sid)]={k:row.get(k) for k in ("id","name","name_cn","date","platform","rating","meta_tags","tags")}
            print(sid,row.get("name_cn")or row.get("name"),row.get("rating",{}).get("score"),flush=True)
        except urllib.error.HTTPError as error:
            out["errors"].append({"subject_id":sid,"http_status":error.code})
            if error.code in (401,403,429):
                write_json(data/"live_verification.json",out)
                break
        except (ValueError,TimeoutError,urllib.error.URLError) as error:
            out["errors"].append({"subject_id":sid,"error_type":type(error).__name__})
        write_json(data/"live_verification.json",out)
    write_json(data/"live_verification.json",out)


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data",type=Path,default=HERE.parent/"recommend_dataset/data/semantic_hybrid_v1")
    run(parser.parse_args().data)
