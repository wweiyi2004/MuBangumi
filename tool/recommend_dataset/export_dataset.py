#!/usr/bin/env python3
"""Phase 1c: export the collected raw records into the final dataset files.

Writes (under cfg.output.export_dir, default <data_dir>/export):
  subjects.csv, interactions.csv, train/validation/test_interactions.csv,
  item_features.jsonl, dataset_report.json

The split assignment is temporal by interaction.updated_at; nothing is
randomized. Metadata-missing anime references remain usable by collaborative
models and are counted separately; known non-anime/permanently unavailable
references are blocked.

Usage:
  python tool/recommend_dataset/export_dataset.py --config dataset_config.json
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from src import db, export
from src.config import load_config


def main() -> int:
    parser = argparse.ArgumentParser(description="Export the collected dataset")
    parser.add_argument("--config", default="dataset_config.json", help="JSON config file")
    args = parser.parse_args()

    cfg = load_config(args.config)
    store = db.Store(cfg.checkpoint_db)
    try:
        report = export.build_export(store, cfg)
    finally:
        store.close()

    subjects = report["subjects"]
    interactions = report["interactions"]
    print(f"[export] subjects={subjects['total']} (with air date: {subjects['with_air_date']})")
    print(f"[export] interactions={interactions['total']} users={interactions['users']} "
          f"items={interactions['items']} sparsity={interactions['sparsity']}")
    print(
        f"[export] model eligible={interactions.get('training_eligible', interactions['total'])} "
        f"users={interactions.get('training_users', interactions['users'])} "
        f"complete_only={report.get('config', {}).get('complete_only', False)}"
    )
    print(f"[export] invalid refs={interactions['invalid_refs']} "
          f"rated ratio={interactions['rated_ratio']}")
    for name in ("train", "validation", "test"):
        stats = report["splits"][name]
        print(f"[export] {name:<11} users={stats['users']} items={stats['items']} "
              f"interactions={stats['interactions']}")
    core = report.get("model_views", {}).get("variants", {}).get("core", {})
    if core:
        print(
            "[export] core "
            + " ".join(
                f"{name}={core[name]['interactions']}"
                for name in ("train", "validation", "test")
            )
        )
    print(f"[export] classes {report['item_classes']}")
    print(f"[export] wrote {len(report['files'])} files to {cfg.export_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
