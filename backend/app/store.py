"""
Persistent records: learners, sessions, and their events.

SQLite from the standard library — one file, no server to run, which is the
right size for a pilot at one school. The interface is small enough to move
to Postgres later without touching the routes.

What is stored: who ran a session, when, what happened at each station, and
the score. What is never stored: camera frames. Detection endpoints process
an image in memory and discard it.
"""
from __future__ import annotations

import json
import os
import sqlite3
import threading
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

from app import scoring

DEFAULT_DB_PATH = Path(__file__).parent.parent / "data" / "spai.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS learners (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    cohort      TEXT NOT NULL DEFAULT '',
    is_demo     INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
    id                  TEXT PRIMARY KEY,
    learner_id          TEXT REFERENCES learners(id) ON DELETE CASCADE,
    learner_name        TEXT NOT NULL DEFAULT 'Guest',
    role                TEXT NOT NULL DEFAULT 'Trainee',
    mode                TEXT NOT NULL DEFAULT 'assessed',
    headset             TEXT NOT NULL DEFAULT '',
    started_at          TEXT NOT NULL,
    ended_at            TEXT NOT NULL,
    duration_s          INTEGER NOT NULL DEFAULT 0,
    completed           INTEGER NOT NULL DEFAULT 0,
    stations_completed  INTEGER NOT NULL DEFAULT 0,
    contamination_count INTEGER NOT NULL DEFAULT 0,
    score               INTEGER NOT NULL DEFAULT 0,
    verdict             TEXT NOT NULL DEFAULT 'incomplete',
    detail              TEXT NOT NULL DEFAULT '{}',
    received_at         TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    at          TEXT NOT NULL,
    kind        TEXT NOT NULL,
    station     TEXT,
    message     TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_sessions_learner ON sessions(learner_id, started_at);
CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id, id);
"""


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Store:
    """All database access goes through here."""

    def __init__(self, path: str | Path | None = None) -> None:
        self.path = str(path or os.getenv("SPAI_DB") or DEFAULT_DB_PATH)
        if self.path != ":memory:":
            Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        # One connection guarded by a lock: requests run in a thread pool,
        # and SQLite wants one writer at a time anyway.
        self._db = sqlite3.connect(self.path, check_same_thread=False)
        self._db.row_factory = sqlite3.Row
        self._db.execute("PRAGMA foreign_keys = ON")
        self._lock = threading.RLock()
        with self._lock:
            self._db.executescript(SCHEMA)
            self._db.commit()

    def close(self) -> None:
        with self._lock:
            self._db.close()

    # ---- learners ---------------------------------------------------------

    def add_learner(self, name: str, cohort: str = "", is_demo: bool = False, learner_id: str | None = None) -> dict:
        learner = {
            "id": learner_id or uuid.uuid4().hex[:12],
            "name": name.strip(),
            "cohort": cohort.strip(),
            "is_demo": bool(is_demo),
            "created_at": now_iso(),
        }
        with self._lock:
            self._db.execute(
                "INSERT INTO learners (id, name, cohort, is_demo, created_at) VALUES (?, ?, ?, ?, ?)",
                (learner["id"], learner["name"], learner["cohort"], int(is_demo), learner["created_at"]),
            )
            self._db.commit()
        return learner

    def get_learner(self, learner_id: str) -> dict | None:
        with self._lock:
            row = self._db.execute("SELECT * FROM learners WHERE id = ?", (learner_id,)).fetchone()
        return self._learner(row) if row else None

    def list_learners(self) -> list[dict]:
        with self._lock:
            rows = self._db.execute("SELECT * FROM learners ORDER BY cohort, name COLLATE NOCASE").fetchall()
        return [self._learner(r) for r in rows]

    def delete_learner(self, learner_id: str) -> bool:
        """Erase a learner and every session and event recorded for them."""
        with self._lock:
            cur = self._db.execute("DELETE FROM learners WHERE id = ?", (learner_id,))
            self._db.commit()
            return cur.rowcount > 0

    def delete_demo_data(self) -> int:
        with self._lock:
            cur = self._db.execute("DELETE FROM learners WHERE is_demo = 1")
            self._db.commit()
            return cur.rowcount

    @staticmethod
    def _learner(row: sqlite3.Row) -> dict:
        return {"id": row["id"], "name": row["name"], "cohort": row["cohort"],
                "is_demo": bool(row["is_demo"]), "created_at": row["created_at"]}

    # ---- sessions ---------------------------------------------------------

    def save_session(self, record: dict, rubric: dict | None = None) -> dict:
        """Insert or replace one session. Scoring happens here, so the score
        of record is always the server's, whatever the headset computed.

        Uploading the same session id twice replaces it — a headset that
        retries after a dropped connection can't create duplicates.
        """
        events = record.get("events") or []
        result = scoring.score_session(record, rubric)
        learner_id = record.get("learner_id")
        learner_name = record.get("learner_name") or "Guest"
        if learner_id:
            learner = self.get_learner(learner_id)
            if learner is None:
                learner_id = None          # roster entry was deleted; keep the run as a guest run
            else:
                learner_name = learner["name"]

        detail = {
            "result": result,
            "instruments_seen": record.get("instruments_seen") or [],
            "app_version": record.get("app_version") or "",
            "detection_mode": record.get("detection_mode") or "",
        }
        row = (
            record["id"], learner_id, learner_name,
            record.get("role") or "Trainee", record.get("mode") or "assessed", record.get("headset") or "",
            record["started_at"], record["ended_at"], int(record.get("duration_s") or 0),
            int(bool(record.get("completed"))), int(record.get("stations_completed") or 0),
            sum(1 for e in events if e.get("kind") == "contamination"),
            result["score"], result["verdict"], json.dumps(detail), now_iso(),
        )
        with self._lock:
            self._db.execute("DELETE FROM sessions WHERE id = ?", (record["id"],))
            self._db.execute(
                """INSERT INTO sessions (id, learner_id, learner_name, role, mode, headset, started_at, ended_at,
                       duration_s, completed, stations_completed, contamination_count, score, verdict, detail, received_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", row)
            self._db.executemany(
                "INSERT INTO events (session_id, at, kind, station, message) VALUES (?, ?, ?, ?, ?)",
                [(record["id"], e.get("at") or record["started_at"], e.get("kind") or "info",
                  e.get("station"), (e.get("message") or "")[:300]) for e in events],
            )
            self._db.commit()
        return self.get_session(record["id"])  # type: ignore[return-value]

    def get_session(self, session_id: str) -> dict | None:
        with self._lock:
            row = self._db.execute("SELECT * FROM sessions WHERE id = ?", (session_id,)).fetchone()
            if row is None:
                return None
            events = self._db.execute(
                "SELECT at, kind, station, message FROM events WHERE session_id = ? ORDER BY id", (session_id,)
            ).fetchall()
        session = self._session(row)
        session["events"] = [dict(e) for e in events]
        return session

    def list_sessions(self, learner_id: str | None = None, limit: int = 500) -> list[dict]:
        query, args = "SELECT * FROM sessions", []
        if learner_id:
            query += " WHERE learner_id = ?"
            args.append(learner_id)
        query += " ORDER BY started_at DESC LIMIT ?"
        args.append(limit)
        with self._lock:
            rows = self._db.execute(query, args).fetchall()
        return [self._session(r) for r in rows]

    def delete_session(self, session_id: str) -> bool:
        with self._lock:
            cur = self._db.execute("DELETE FROM sessions WHERE id = ?", (session_id,))
            self._db.commit()
            return cur.rowcount > 0

    def purge_older_than(self, days: int) -> int:
        """Retention: remove sessions that ended more than `days` ago."""
        cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat(timespec="seconds")
        with self._lock:
            cur = self._db.execute("DELETE FROM sessions WHERE ended_at < ?", (cutoff,))
            self._db.commit()
            return cur.rowcount

    @staticmethod
    def _session(row: sqlite3.Row) -> dict:
        detail = json.loads(row["detail"] or "{}")
        return {
            "id": row["id"], "learner_id": row["learner_id"], "learner_name": row["learner_name"],
            "role": row["role"], "mode": row["mode"], "headset": row["headset"],
            "started_at": row["started_at"], "ended_at": row["ended_at"], "duration_s": row["duration_s"],
            "completed": bool(row["completed"]), "stations_completed": row["stations_completed"],
            "contamination_count": row["contamination_count"], "score": row["score"], "verdict": row["verdict"],
            "verdict_label": scoring.VERDICT_LABELS.get(row["verdict"], row["verdict"]),
            "result": detail.get("result") or {},
            "instruments_seen": detail.get("instruments_seen") or [],
            "app_version": detail.get("app_version") or "",
            "detection_mode": detail.get("detection_mode") or "",
        }

    # ---- roll-ups for the instructor dashboard ----------------------------

    def overview(self) -> dict:
        learners = self.list_learners()
        sessions = [s for s in self.list_sessions(limit=5000) if s["mode"] == "assessed"]
        by_learner: dict[str, list[dict]] = {}
        for s in sessions:
            if s["learner_id"]:
                by_learner.setdefault(s["learner_id"], []).append(s)

        roster = []
        for learner in learners:
            runs = sorted(by_learner.get(learner["id"], []), key=lambda s: s["started_at"])
            latest = runs[-1] if runs else None
            roster.append({
                **learner,
                "runs": len(runs),
                "last_run_at": latest["started_at"] if latest else None,
                "latest_score": latest["score"] if latest else None,
                "latest_verdict": latest["verdict"] if latest else None,
                "latest_verdict_label": latest["verdict_label"] if latest else "No runs yet",
                "best_score": max((r["score"] for r in runs if r["completed"]), default=None),
                "scores": [r["score"] for r in runs][-12:],
                "competent": any(r["verdict"] == scoring.VERDICT_COMPETENT for r in runs),
            })

        # Which station trips people up most — the first thing to re-teach.
        trouble = {key: 0 for key in scoring.STATIONS}
        for s in sessions:
            for st in s["result"].get("stations", []):
                trouble[st["station"]] += st["contamination"] + st["send_back"] + st["count_mismatch"] + st["redo"]
        hardest = max(trouble, key=trouble.get) if any(trouble.values()) else None

        completed = [s for s in sessions if s["completed"]]
        with_runs = [r for r in roster if r["runs"]]
        return {
            "learners": len(learners),
            "learners_with_runs": len(with_runs),
            "learners_competent": sum(1 for r in roster if r["competent"]),
            "sessions": len(sessions),
            "sessions_completed": len(completed),
            "average_score": round(sum(s["score"] for s in completed) / len(completed)) if completed else None,
            "contamination_events": sum(s["contamination_count"] for s in sessions),
            "station_trouble": [{"station": k, "title": scoring.STATION_TITLES[k], "issues": v} for k, v in trouble.items()],
            "hardest_station": scoring.STATION_TITLES[hardest] if hardest else None,
            "roster": roster,
            "has_demo_data": any(l["is_demo"] for l in learners),
        }


_store: Store | None = None


def get_store() -> Store:
    """The process-wide store, created on first use."""
    global _store
    if _store is None:
        _store = Store()
    return _store


def use_store(store: Store | None) -> None:
    """Swap the store (tests point this at a temporary database)."""
    global _store
    _store = store
