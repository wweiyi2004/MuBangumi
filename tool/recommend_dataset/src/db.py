"""SQLite persistence: upserts, checkpoints, run stats, seed-user bookkeeping.

Everything written here lives under the git-ignored data directory. The
checkpoint database is operational state for resume / idempotency and is never
part of the exported dataset. Interaction rows and pagination checkpoints use
anonymous_user_id. The local seed_users table retains usernames solely for
resume bookkeeping and is never exported.
"""
from __future__ import annotations

import sqlite3
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Optional

SCHEMA = """
CREATE TABLE IF NOT EXISTS subjects (
    subject_id INTEGER PRIMARY KEY,
    name TEXT, name_cn TEXT,
    air_date TEXT, year INTEGER, season INTEGER,
    platform TEXT, episode_count INTEGER, summary TEXT,
    tags_json TEXT, meta_tags_json TEXT, infobox_json TEXT,
    score REAL, rank INTEGER, rating_total INTEGER, collection_total INTEGER,
    wish_count INTEGER, doing_count INTEGER, collect_count INTEGER,
    on_hold_count INTEGER, dropped_count INTEGER,
    image_url TEXT,
    production_json TEXT, director_json TEXT, series_composer_json TEXT,
    original_work_json TEXT, music_json TEXT,
    voice_actors_json TEXT, related_json TEXT, persons_json TEXT,
    nsfw INTEGER NOT NULL DEFAULT 0,
    fetched_at TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    error TEXT,
    attempts INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS interactions (
    anon_user_id TEXT NOT NULL,
    subject_id INTEGER NOT NULL,
    collection_type INTEGER NOT NULL,
    collection_type_name TEXT NOT NULL,
    user_rating INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT,
    fetched_at TEXT,
    PRIMARY KEY (anon_user_id, subject_id)
);
CREATE INDEX IF NOT EXISTS idx_interactions_subject ON interactions(subject_id);
CREATE TABLE IF NOT EXISTS checkpoints (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS run_stats (
    run_id TEXT PRIMARY KEY,
    stage TEXT NOT NULL,
    started_at TEXT NOT NULL,
    finished_at TEXT,
    success INTEGER NOT NULL DEFAULT 0,
    failed INTEGER NOT NULL DEFAULT 0,
    skipped INTEGER NOT NULL DEFAULT 0,
    truncated INTEGER NOT NULL DEFAULT 0,
    retries INTEGER NOT NULL DEFAULT 0,
    cursor_text TEXT
);
CREATE TABLE IF NOT EXISTS seed_users (
    username TEXT PRIMARY KEY,
    anon_user_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    items_fetched INTEGER NOT NULL DEFAULT 0,
    pages_fetched INTEGER NOT NULL DEFAULT 0,
    next_offset INTEGER NOT NULL DEFAULT 0,
    total_reported INTEGER,
    is_complete INTEGER NOT NULL DEFAULT 0,
    stop_reason TEXT,
    last_success_at TEXT,
    last_error TEXT,
    source TEXT NOT NULL DEFAULT 'seed_file',
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS known_subjects (
    subject_id INTEGER PRIMARY KEY,
    subject_type INTEGER,
    name TEXT,
    status TEXT NOT NULL DEFAULT 'checked',
    error TEXT,
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value INTEGER NOT NULL DEFAULT 0
);
"""

SUBJECT_COLUMNS = [
    "subject_id", "name", "name_cn", "air_date", "year", "season", "platform",
    "episode_count", "summary", "tags_json", "meta_tags_json", "infobox_json",
    "score", "rank", "rating_total", "collection_total",
    "wish_count", "doing_count", "collect_count", "on_hold_count", "dropped_count",
    "image_url", "production_json", "director_json", "series_composer_json",
    "original_work_json", "music_json", "voice_actors_json", "related_json",
    "persons_json", "nsfw", "fetched_at", "status", "error", "attempts",
]


def _utcnow() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


class Store:
    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self._path = path
        self._conn = sqlite3.connect(str(path), check_same_thread=False)
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA synchronous=NORMAL")
        self._lock = threading.RLock()
        with self._lock:
            self._conn.executescript(SCHEMA)
            self._migrate_seed_users()
            self._ensure_column(
                "run_stats", "truncated", "INTEGER NOT NULL DEFAULT 0"
            )
            for key in ("subjects_inserted", "subjects_updated",
                        "interactions_inserted", "interactions_updated"):
                self._conn.execute(
                    "INSERT OR IGNORE INTO meta(key, value) VALUES(?, 0)", (key,)
                )
            self._conn.commit()

    def _ensure_column(self, table: str, name: str, declaration: str) -> None:
        existing = {
            str(row[1])
            for row in self._conn.execute(f"PRAGMA table_info({table})")
        }
        if name not in existing:
            self._conn.execute(
                f"ALTER TABLE {table} ADD COLUMN {name} {declaration}"
            )

    def _migrate_seed_users(self) -> None:
        """Add completeness fields to Phase-1 databases in place.

        Legacy ``ok`` rows intentionally remain incomplete: the old collector
        did not persist the API total and marked page-budget stops as success,
        so their completeness cannot be reconstructed safely. Empty responses
        are the only legacy terminal state that can be trusted.
        """
        existing = {
            str(row[1]) for row in self._conn.execute("PRAGMA table_info(seed_users)")
        }
        additions = {
            "pages_fetched": "INTEGER NOT NULL DEFAULT 0",
            "next_offset": "INTEGER NOT NULL DEFAULT 0",
            "total_reported": "INTEGER",
            "is_complete": "INTEGER NOT NULL DEFAULT 0",
            "stop_reason": "TEXT",
            "last_success_at": "TEXT",
            "last_error": "TEXT",
            "source": "TEXT NOT NULL DEFAULT 'seed_file'",
        }
        for name, declaration in additions.items():
            if name not in existing:
                self._conn.execute(
                    f"ALTER TABLE seed_users ADD COLUMN {name} {declaration}"
                )
        self._conn.execute(
            "UPDATE seed_users SET is_complete=1, "
            "stop_reason=COALESCE(stop_reason, 'legacy_empty') "
            "WHERE status='empty'"
        )

    def close(self) -> None:
        with self._lock:
            self._conn.close()

    # ------------------------------------------------------------------ subjects
    def upsert_subject(self, record: dict[str, Any]) -> str:
        """Insert or update by subject_id; returns 'inserted' or 'updated'."""
        subject_id = record["subject_id"]
        columns = [c for c in SUBJECT_COLUMNS if c in record and c != "subject_id"]
        with self._lock:
            cur = self._conn.execute(
                "INSERT OR IGNORE INTO subjects(subject_id) VALUES(?)", (subject_id,)
            )
            inserted = cur.rowcount == 1
            set_clause = ",".join(f"{col} = ?" for col in columns)
            self._conn.execute(
                f"UPDATE subjects SET {set_clause} WHERE subject_id = ?",
                [record[c] for c in columns] + [subject_id],
            )
            self._conn.commit()
        if inserted:
            self._increment_meta("subjects_inserted")
            return "inserted"
        self._increment_meta("subjects_updated")
        return "updated"

    def _increment_meta(self, key: str) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO meta(key, value) VALUES(?, 1) "
                "ON CONFLICT(key) DO UPDATE SET value = value + 1",
                (key,),
            )
            self._conn.commit()

    def meta_value(self, key: str) -> int:
        with self._lock:
            row = self._conn.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
        return int(row[0]) if row else 0

    def subject_status(self, subject_id: int) -> Optional[str]:
        with self._lock:
            row = self._conn.execute(
                "SELECT status FROM subjects WHERE subject_id = ?", (subject_id,)
            ).fetchone()
        return row[0] if row else None

    def mark_subject_status(self, subject_id: int, status: str, error: Optional[str] = None) -> None:
        with self._lock:
            self._conn.execute(
                "UPDATE subjects SET status = ?, error = ?, attempts = attempts + 1 "
                "WHERE subject_id = ?",
                (status, error, subject_id),
            )
            self._conn.commit()

    def subjects_needing_fetch(self, ids: list[int]) -> list[int]:
        """Ids whose status is fresh/pending/failed (excludes ok/permanent/skipped)."""
        result: list[int] = []
        with self._lock:
            for sid in ids:
                row = self._conn.execute(
                    "SELECT status FROM subjects WHERE subject_id = ?", (sid,)
                ).fetchone()
                status = row[0] if row else None
                if status in (None, "pending", "failed"):
                    result.append(sid)
        return result

    def list_subjects(self, statuses: Optional[tuple[str, ...]] = None) -> list[dict[str, Any]]:
        """All subject rows, optionally filtered by status (e.g. ("ok",))."""
        where = ""
        args: tuple = ()
        if statuses:
            placeholders = ",".join("?" for _ in statuses)
            where = f"WHERE status IN ({placeholders})"
            args = tuple(statuses)
        with self._lock:
            rows = self._conn.execute(
                f"SELECT {','.join(SUBJECT_COLUMNS)} FROM subjects {where}", args
            ).fetchall()
        return [dict(zip(SUBJECT_COLUMNS, row)) for row in rows]

    def subject_count(self, statuses: Optional[tuple[str, ...]] = None) -> int:
        where = ""
        args: tuple = ()
        if statuses:
            placeholders = ",".join("?" for _ in statuses)
            where = f"WHERE status IN ({placeholders})"
            args = tuple(statuses)
        with self._lock:
            row = self._conn.execute(
                f"SELECT COUNT(*) FROM subjects {where}", args
            ).fetchone()
        return int(row[0])

    def claim_subject(self, subject_id: int) -> str:
        """Reserve a subject id as a pending row; returns 'inserted' or 'existing'.

        Placeholder rows carry the fetch state (pending -> ok/permanent/failed),
        which is what makes --from-interactions resume-safe and idempotent.
        """
        with self._lock:
            cur = self._conn.execute(
                "INSERT OR IGNORE INTO subjects(subject_id) VALUES(?)", (subject_id,)
            )
            self._conn.commit()
        return "inserted" if cur.rowcount == 1 else "existing"

    # -------------------------------------------------------------- interactions
    def upsert_interaction(self, row: dict[str, Any]) -> str:
        """Upsert by (anon_user_id, subject_id); returns 'inserted' or 'updated'."""
        with self._lock:
            cur = self._conn.execute(
                "INSERT OR IGNORE INTO interactions "
                "(anon_user_id, subject_id, collection_type, collection_type_name, "
                " user_rating, updated_at, fetched_at) VALUES (?,?,?,?,?,?,?)",
                (
                    row["anon_user_id"],
                    row["subject_id"],
                    row["collection_type"],
                    row["collection_type_name"],
                    row["user_rating"],
                    row["updated_at"],
                    row["fetched_at"],
                ),
            )
            if cur.rowcount == 1:
                self._conn.commit()
                self._increment_meta("interactions_inserted")
                return "inserted"
            self._conn.execute(
                "UPDATE interactions SET collection_type = ?, collection_type_name = ?, "
                "user_rating = ?, updated_at = ?, fetched_at = ? "
                "WHERE anon_user_id = ? AND subject_id = ?",
                (
                    row["collection_type"],
                    row["collection_type_name"],
                    row["user_rating"],
                    row["updated_at"],
                    row["fetched_at"],
                    row["anon_user_id"],
                    row["subject_id"],
                ),
            )
            self._conn.commit()
            self._increment_meta("interactions_updated")
            return "updated"

    def list_interactions(self) -> list[dict[str, Any]]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT anon_user_id, subject_id, collection_type, collection_type_name, "
                "user_rating, updated_at, fetched_at FROM interactions"
            ).fetchall()
        columns = [
            "anon_user_id", "subject_id", "collection_type", "collection_type_name",
            "user_rating", "updated_at", "fetched_at",
        ]
        return [dict(zip(columns, row)) for row in rows]

    def interaction_count(self) -> int:
        with self._lock:
            row = self._conn.execute("SELECT COUNT(*) FROM interactions").fetchone()
        return int(row[0])

    def user_interaction_count(self, anonymous_user_id: str) -> int:
        with self._lock:
            row = self._conn.execute(
                "SELECT COUNT(*) FROM interactions WHERE anon_user_id = ?",
                (anonymous_user_id,),
            ).fetchone()
        return int(row[0])

    def prune_user_interactions(
        self, anonymous_user_id: str, current_snapshot_marker: str
    ) -> int:
        """Remove rows not observed during a completed refetch snapshot."""
        with self._lock:
            cur = self._conn.execute(
                "DELETE FROM interactions WHERE anon_user_id = ? AND fetched_at != ?",
                (anonymous_user_id, current_snapshot_marker),
            )
            self._conn.commit()
        return int(cur.rowcount)

    # --------------------------------------------------- interaction backfill
    def list_interaction_subject_ids(self) -> list[int]:
        """Distinct subject_ids referenced by any collected interaction."""
        with self._lock:
            rows = self._conn.execute(
                "SELECT DISTINCT subject_id FROM interactions ORDER BY subject_id"
            ).fetchall()
        return [int(row[0]) for row in rows]

    def list_missing_interaction_subject_ids(self) -> list[int]:
        """Interaction-referenced subject_ids with no row in the subjects table."""
        with self._lock:
            rows = self._conn.execute(
                "SELECT DISTINCT i.subject_id FROM interactions i "
                "LEFT JOIN subjects s ON s.subject_id = i.subject_id "
                "WHERE s.subject_id IS NULL ORDER BY i.subject_id"
            ).fetchall()
        return [int(row[0]) for row in rows]

    def list_failed_interaction_subject_ids(self) -> list[int]:
        """Interaction-referenced subject_ids whose fetch previously failed."""
        with self._lock:
            rows = self._conn.execute(
                "SELECT DISTINCT i.subject_id FROM interactions i "
                "JOIN subjects s ON s.subject_id = i.subject_id "
                "WHERE s.status = 'failed' ORDER BY i.subject_id"
            ).fetchall()
        return [int(row[0]) for row in rows]

    def list_retryable_interaction_subject_ids(self) -> list[int]:
        """Interaction subjects claimed but not completed successfully."""
        with self._lock:
            rows = self._conn.execute(
                "SELECT DISTINCT i.subject_id FROM interactions i "
                "JOIN subjects s ON s.subject_id = i.subject_id "
                "WHERE s.status IN ('pending','failed') ORDER BY i.subject_id"
            ).fetchall()
        return [int(row[0]) for row in rows]

    def list_known_non_anime_ids(self) -> set[int]:
        """Subject ids already checked and known to be non-anime."""
        with self._lock:
            rows = self._conn.execute(
                "SELECT subject_id FROM known_subjects WHERE subject_type IS NOT NULL "
                "AND subject_type != 2"
            ).fetchall()
        return {int(row[0]) for row in rows}

    def list_blocked_interaction_subject_ids(self) -> set[int]:
        """Items that must not enter training: known non-anime or permanently gone."""
        with self._lock:
            rows = self._conn.execute(
                "SELECT subject_id FROM subjects WHERE status = 'permanent' "
                "UNION "
                "SELECT subject_id FROM known_subjects "
                "WHERE subject_type IS NOT NULL AND subject_type != 2"
            ).fetchall()
        return {int(row[0]) for row in rows}

    def record_known_subject(
        self, subject_id: int, subject_type: Optional[int], name: Optional[str],
        error: Optional[str] = None,
    ) -> None:
        """Remember that a subject id was checked (used for non-anime ids)."""
        with self._lock:
            self._conn.execute(
                "INSERT INTO known_subjects(subject_id, subject_type, name, status, error, updated_at) "
                "VALUES(?,?,?,'checked',?,?) "
                "ON CONFLICT(subject_id) DO UPDATE SET subject_type = excluded.subject_type, "
                "name = excluded.name, status = excluded.status, error = excluded.error, "
                "updated_at = excluded.updated_at",
                (subject_id, subject_type, name, error, _utcnow()),
            )
            self._conn.commit()

    def delete_subject(self, subject_id: int) -> None:
        """Remove a placeholder subject row (used when an id turns out non-anime)."""
        with self._lock:
            self._conn.execute("DELETE FROM subjects WHERE subject_id = ?", (subject_id,))
            self._conn.commit()

    # --------------------------------------------------------------- checkpoints
    def get_checkpoint(self, key: str) -> Optional[str]:
        with self._lock:
            row = self._conn.execute(
                "SELECT value FROM checkpoints WHERE key = ?", (key,)
            ).fetchone()
        return row[0] if row else None

    def set_checkpoint(self, key: str, value: str) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO checkpoints(key, value, updated_at) VALUES(?,?,?) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value, "
                "updated_at = excluded.updated_at",
                (key, value, _utcnow()),
            )
            self._conn.commit()

    def clear_checkpoints(self, key_prefix: str) -> int:
        """Delete all checkpoints with the given prefix; returns rows removed."""
        with self._lock:
            cur = self._conn.execute(
                "DELETE FROM checkpoints WHERE key LIKE ?", (key_prefix + "%",)
            )
            self._conn.commit()
        return cur.rowcount


    # ----------------------------------------------------------------- run stats
    def start_run(self, stage: str) -> str:
        run_id = uuid.uuid4().hex
        with self._lock:
            self._conn.execute(
                "INSERT INTO run_stats(run_id, stage, started_at) VALUES(?,?,?)",
                (run_id, stage, _utcnow()),
            )
            self._conn.commit()
        return run_id

    def finish_run(self, run_id: str, stats: dict[str, Any]) -> None:
        with self._lock:
            self._conn.execute(
                "UPDATE run_stats SET finished_at = ?, success = ?, failed = ?, "
                "skipped = ?, truncated = ?, retries = ?, cursor_text = ? "
                "WHERE run_id = ?",
                (
                    _utcnow(),
                    stats.get("success", 0),
                    stats.get("failed", 0),
                    stats.get("skipped", 0),
                    stats.get("truncated", 0),
                    stats.get("retries", 0),
                    stats.get("cursor", ""),
                    run_id,
                ),
            )
            self._conn.commit()

    def aggregate_stats(self, stage: Optional[str] = None) -> dict[str, int]:
        where = "WHERE stage = ?" if stage else ""
        args = (stage,) if stage else ()
        with self._lock:
            row = self._conn.execute(
                f"SELECT COALESCE(SUM(success),0), COALESCE(SUM(failed),0), "
                f"COALESCE(SUM(skipped),0), COALESCE(SUM(truncated),0), "
                f"COALESCE(SUM(retries),0), COUNT(*) "
                f"FROM run_stats {where}",
                args,
            ).fetchone()
        return {
            "success": int(row[0]),
            "failed": int(row[1]),
            "skipped": int(row[2]),
            "truncated": int(row[3]),
            "retries": int(row[4]),
            "runs": int(row[5]),
        }

    # ---------------------------------------------------------------- seed users
    def seed_user_status(self, username: str) -> Optional[str]:
        with self._lock:
            row = self._conn.execute(
                "SELECT status, items_fetched FROM seed_users WHERE username = ?", (username,)
            ).fetchone()
        return row[0] if row else None

    def seed_user_record(self, username: str) -> Optional[dict[str, Any]]:
        columns = [
            "status", "items_fetched", "pages_fetched", "next_offset",
            "total_reported", "is_complete", "stop_reason",
            "last_success_at", "last_error", "source",
        ]
        with self._lock:
            row = self._conn.execute(
                f"SELECT {','.join(columns)} FROM seed_users WHERE username = ?",
                (username,),
            ).fetchone()
        if row is None:
            return None
        record = dict(zip(columns, row))
        record["is_complete"] = bool(record["is_complete"])
        return record

    def set_seed_user(
        self,
        username: str,
        anon_user_id: str,
        status: str,
        items: int,
        *,
        pages_fetched: int = 0,
        next_offset: int = 0,
        total_reported: Optional[int] = None,
        is_complete: Optional[bool] = None,
        stop_reason: Optional[str] = None,
        last_error: Optional[str] = None,
        source: str = "seed_file",
    ) -> None:
        complete = (
            status in ("complete", "empty")
            if is_complete is None
            else is_complete
        )
        success_at = _utcnow() if status in ("complete", "empty") else None
        with self._lock:
            self._conn.execute(
                "INSERT INTO seed_users("
                "username, anon_user_id, status, items_fetched, pages_fetched, "
                "next_offset, total_reported, is_complete, stop_reason, "
                "last_success_at, last_error, source, updated_at"
                ") VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) "
                "ON CONFLICT(username) DO UPDATE SET "
                "anon_user_id=excluded.anon_user_id, status=excluded.status, "
                "items_fetched=excluded.items_fetched, "
                "pages_fetched=excluded.pages_fetched, "
                "next_offset=excluded.next_offset, "
                "total_reported=excluded.total_reported, "
                "is_complete=excluded.is_complete, "
                "stop_reason=excluded.stop_reason, "
                "last_success_at=COALESCE(excluded.last_success_at, seed_users.last_success_at), "
                "last_error=excluded.last_error, source=excluded.source, "
                "updated_at=excluded.updated_at",
                (
                    username, anon_user_id, status, items, pages_fetched,
                    next_offset, total_reported, int(complete), stop_reason,
                    success_at, last_error, source, _utcnow(),
                ),
            )
            self._conn.commit()

    def seed_user_summary(self) -> dict[str, int]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT status, COUNT(*) FROM seed_users GROUP BY status"
            ).fetchall()
        return {status: int(count) for status, count in rows}

    def user_collection_states(self) -> dict[str, dict[str, Any]]:
        """Return export-safe collection state keyed by anonymous user id.

        The local ``seed_users`` table contains the original username for
        resumability.  This method deliberately selects neither that username
        nor any other identifying value, so callers cannot accidentally place
        it in a dataset export.
        """
        with self._lock:
            rows = self._conn.execute(
                "SELECT anon_user_id, status, is_complete, stop_reason "
                "FROM seed_users"
            ).fetchall()
        return {
            str(anonymous_id): {
                "status": str(status),
                "is_complete": bool(is_complete),
                "stop_reason": stop_reason,
            }
            for anonymous_id, status, is_complete, stop_reason in rows
        }

    def seed_user_completeness_summary(self) -> dict[str, int]:
        with self._lock:
            row = self._conn.execute(
                "SELECT COUNT(*), "
                "COALESCE(SUM(CASE WHEN is_complete=1 THEN 1 ELSE 0 END),0), "
                "COALESCE(SUM(CASE WHEN is_complete=0 THEN 1 ELSE 0 END),0) "
                "FROM seed_users"
            ).fetchone()
        return {
            "requested": int(row[0]),
            "complete": int(row[1]),
            "incomplete": int(row[2]),
        }
