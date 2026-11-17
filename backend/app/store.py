"""
Persistent records for every school on one SPAI server.

The model
---------
An **organization** is one school program or hospital department. Everything
else belongs to exactly one organization, and every read and write below
takes the organization's id and filters on it. There is no query in this
file that can return one school's rows to another school; the tests in
tests/test_tenancy.py try.

  organizations
    instructors      people who sign in to the dashboard (email + password)
    devices          paired headsets; each holds its own secret token
    learners         students; each has a 4-digit PIN they enter on the headset
    sessions/events  runs uploaded by a paired headset for a signed-in learner
    protocol         the school's station scripts, count sheet and rubric
    audit            who did what in the dashboard

Secrets (passwords, session tokens, device tokens, pairing codes, invite
tokens, PINs) are only ever stored hashed. Camera frames are never stored.

SQLite from the standard library: one file, no server to run. The interface
is small enough to move to Postgres without touching the routes.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import threading
import time
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

from app import scoring

DEFAULT_DB_PATH = Path(__file__).parent.parent / "data" / "spai.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS orgs (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    created_at  TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS instructors (
    id          TEXT PRIMARY KEY,
    org_id      TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    email       TEXT NOT NULL UNIQUE COLLATE NOCASE,
    name        TEXT NOT NULL,
    role        TEXT NOT NULL CHECK (role IN ('admin', 'instructor')),
    pw_hash     TEXT NOT NULL,
    disabled    INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS logins (
    token_hash    TEXT PRIMARY KEY,
    instructor_id TEXT NOT NULL REFERENCES instructors(id) ON DELETE CASCADE,
    expires_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS invites (
    token_hash  TEXT PRIMARY KEY,
    org_id      TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    email       TEXT NOT NULL,
    role        TEXT NOT NULL,
    expires_at  INTEGER NOT NULL,
    used        INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS devices (
    id            TEXT PRIMARY KEY,
    org_id        TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    name          TEXT NOT NULL,
    token_hash    TEXT NOT NULL UNIQUE,
    created_at    TEXT NOT NULL,
    last_seen_at  TEXT,
    revoked       INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS pairing_codes (
    code_hash   TEXT PRIMARY KEY,
    org_id      TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    expires_at  INTEGER NOT NULL,
    used        INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS learners (
    id            TEXT PRIMARY KEY,
    org_id        TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    name          TEXT NOT NULL,
    cohort        TEXT NOT NULL DEFAULT '',
    is_demo       INTEGER NOT NULL DEFAULT 0,
    pin_hash      TEXT NOT NULL,
    failed_pins   INTEGER NOT NULL DEFAULT 0,
    locked_until  INTEGER NOT NULL DEFAULT 0,
    created_at    TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
    org_id              TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    id                  TEXT NOT NULL,
    learner_id          TEXT REFERENCES learners(id) ON DELETE CASCADE,
    learner_name        TEXT NOT NULL,
    device_id           TEXT,
    identity            TEXT NOT NULL DEFAULT 'verified',
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
    received_at         TEXT NOT NULL,
    PRIMARY KEY (org_id, id)
);
CREATE TABLE IF NOT EXISTS events (
    seq         INTEGER PRIMARY KEY AUTOINCREMENT,
    org_id      TEXT NOT NULL,
    session_id  TEXT NOT NULL,
    at          TEXT NOT NULL,
    kind        TEXT NOT NULL,
    station     TEXT,
    message     TEXT NOT NULL DEFAULT '',
    FOREIGN KEY (org_id, session_id) REFERENCES sessions(org_id, id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS protocols (
    org_id      TEXT PRIMARY KEY REFERENCES orgs(id) ON DELETE CASCADE,
    body        TEXT NOT NULL,
    version     INTEGER NOT NULL,
    updated_at  TEXT NOT NULL,
    updated_by  TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS audit (
    seq     INTEGER PRIMARY KEY AUTOINCREMENT,
    org_id  TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    at      TEXT NOT NULL,
    actor   TEXT NOT NULL,
    action  TEXT NOT NULL,
    detail  TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_learners_org ON learners(org_id);
CREATE INDEX IF NOT EXISTS idx_sessions_learner ON sessions(org_id, learner_id, started_at);
CREATE INDEX IF NOT EXISTS idx_events_session ON events(org_id, session_id, seq);
CREATE INDEX IF NOT EXISTS idx_devices_org ON devices(org_id);
CREATE INDEX IF NOT EXISTS idx_audit_org ON audit(org_id, seq);
"""

# --- Lifetimes and limits -------------------------------------------------------

LOGIN_TTL = 12 * 3600            # dashboard sign-in lasts a working day
INVITE_TTL = 7 * 24 * 3600       # an instructor invite is good for a week
PAIRING_TTL = 10 * 60            # a headset pairing code is good for ten minutes
PIN_MAX_FAILURES = 5             # wrong PINs before a learner is locked...
PIN_LOCK_SECONDS = 10 * 60       # ...for this long
MIN_PASSWORD_LENGTH = 10

# Pairing codes avoid characters that are easy to misread on a headset
# (0/O, 1/I/L). 30^8 ≈ 6.5e11 combinations, single-use, ten minutes.
PAIRING_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
PAIRING_LENGTH = 8


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _now() -> int:
    return int(time.time())


def _new_id() -> str:
    return uuid.uuid4().hex[:16]


def _sha(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


# --- Password and PIN hashing ---------------------------------------------------

def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return f"scrypt${salt.hex()}${digest.hex()}"


def check_password(password: str, stored: str) -> bool:
    try:
        scheme, salt, digest = stored.split("$")
        if scheme != "scrypt":
            return False
        candidate = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=2**14, r=8, p=1, dklen=32)
        return hmac.compare_digest(candidate.hex(), digest)
    except (ValueError, TypeError):
        return False


def _hash_pin(pin: str, salt: bytes | None = None) -> str:
    salt = salt or secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", pin.encode(), salt, 120_000)
    return f"pbkdf2${salt.hex()}${digest.hex()}"


def _check_pin(pin: str, stored: str) -> bool:
    try:
        _, salt, digest = stored.split("$")
        return hmac.compare_digest(_hash_pin(pin, bytes.fromhex(salt)).split("$")[2], digest)
    except (ValueError, TypeError):
        return False


def new_pin() -> str:
    return f"{secrets.randbelow(10_000):04d}"


def normalize_pairing_code(code: str) -> str:
    return "".join(ch for ch in code.upper() if ch.isalnum())


class StoreError(ValueError):
    """A request that can't be carried out; the message says why, in plain words."""


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
        if self.path != ":memory:":
            self._db.execute("PRAGMA journal_mode = WAL")
        self._lock = threading.RLock()
        with self._lock:
            self._db.executescript(SCHEMA)
            self._db.commit()

    def close(self) -> None:
        with self._lock:
            self._db.close()

    def _one(self, sql: str, args: tuple = ()) -> sqlite3.Row | None:
        with self._lock:
            return self._db.execute(sql, args).fetchone()

    def _all(self, sql: str, args: tuple = ()) -> list[sqlite3.Row]:
        with self._lock:
            return self._db.execute(sql, args).fetchall()

    def _write(self, sql: str, args: tuple = ()) -> int:
        with self._lock:
            cur = self._db.execute(sql, args)
            self._db.commit()
            return cur.rowcount

    def backup(self, destination: str | Path) -> None:
        """A consistent copy of the whole database, safe while the server runs."""
        target = sqlite3.connect(str(destination))
        with self._lock:
            self._db.backup(target)
        target.close()

    # ---- organizations ------------------------------------------------------

    def create_org(self, name: str) -> dict:
        name = name.strip()
        if not name:
            raise StoreError("An organization needs a name.")
        org = {"id": _new_id(), "name": name[:120], "created_at": now_iso()}
        self._write("INSERT INTO orgs (id, name, created_at) VALUES (?, ?, ?)", (org["id"], org["name"], org["created_at"]))
        return org

    def get_org(self, org_id: str) -> dict | None:
        row = self._one("SELECT * FROM orgs WHERE id = ?", (org_id,))
        return dict(row) if row else None

    def list_orgs(self) -> list[dict]:
        return [dict(r) for r in self._all("SELECT * FROM orgs ORDER BY name COLLATE NOCASE")]

    # ---- instructors --------------------------------------------------------

    def create_instructor(self, org_id: str, email: str, name: str, role: str, password: str) -> dict:
        email, name = email.strip().lower(), name.strip()
        if role not in ("admin", "instructor"):
            raise StoreError("Role must be admin or instructor.")
        if "@" not in email or len(email) > 200:
            raise StoreError("Enter a valid email address.")
        if not name:
            raise StoreError("Enter your name.")
        if len(password) < MIN_PASSWORD_LENGTH:
            raise StoreError(f"Use a password of at least {MIN_PASSWORD_LENGTH} characters.")
        if self._one("SELECT 1 FROM instructors WHERE email = ?", (email,)):
            raise StoreError("An account with that email already exists.")
        row = {"id": _new_id(), "org_id": org_id, "email": email, "name": name[:120], "role": role}
        self._write(
            "INSERT INTO instructors (id, org_id, email, name, role, pw_hash, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (row["id"], org_id, email, row["name"], role, hash_password(password), now_iso()),
        )
        return row

    def authenticate(self, email: str, password: str) -> dict | None:
        row = self._one("SELECT * FROM instructors WHERE email = ?", (email.strip().lower(),))
        # Hash even when the email is unknown, so timing doesn't reveal which emails exist.
        stored = row["pw_hash"] if row else hash_password("unknown-account-placeholder")
        if not check_password(password, stored) or row is None or row["disabled"]:
            return None
        return self._instructor(row)

    def get_instructor(self, org_id: str, instructor_id: str) -> dict | None:
        row = self._one("SELECT * FROM instructors WHERE id = ? AND org_id = ?", (instructor_id, org_id))
        return self._instructor(row) if row else None

    def list_instructors(self, org_id: str) -> list[dict]:
        rows = self._all("SELECT * FROM instructors WHERE org_id = ? ORDER BY name COLLATE NOCASE", (org_id,))
        return [self._instructor(r) for r in rows]

    def set_password(self, instructor_id: str, current: str, new: str) -> None:
        row = self._one("SELECT * FROM instructors WHERE id = ?", (instructor_id,))
        if row is None or not check_password(current, row["pw_hash"]):
            raise StoreError("Your current password isn't right.")
        if len(new) < MIN_PASSWORD_LENGTH:
            raise StoreError(f"Use a password of at least {MIN_PASSWORD_LENGTH} characters.")
        self._write("UPDATE instructors SET pw_hash = ? WHERE id = ?", (hash_password(new), instructor_id))
        # Changing a password signs out every other browser.
        self._write("DELETE FROM logins WHERE instructor_id = ?", (instructor_id,))

    def set_disabled(self, org_id: str, instructor_id: str, disabled: bool) -> dict:
        target = self.get_instructor(org_id, instructor_id)
        if target is None:
            raise StoreError("That instructor isn't in your organization.")
        if disabled and target["role"] == "admin" and self._active_admins(org_id) <= 1:
            raise StoreError("This is the only admin. Make someone else an admin first.")
        self._write("UPDATE instructors SET disabled = ? WHERE id = ? AND org_id = ?", (int(disabled), instructor_id, org_id))
        if disabled:
            self._write("DELETE FROM logins WHERE instructor_id = ?", (instructor_id,))
        return self.get_instructor(org_id, instructor_id)  # type: ignore[return-value]

    def set_role(self, org_id: str, instructor_id: str, role: str) -> dict:
        target = self.get_instructor(org_id, instructor_id)
        if target is None:
            raise StoreError("That instructor isn't in your organization.")
        if role not in ("admin", "instructor"):
            raise StoreError("Role must be admin or instructor.")
        if target["role"] == "admin" and role != "admin" and self._active_admins(org_id) <= 1:
            raise StoreError("This is the only admin. Make someone else an admin first.")
        self._write("UPDATE instructors SET role = ? WHERE id = ? AND org_id = ?", (role, instructor_id, org_id))
        return self.get_instructor(org_id, instructor_id)  # type: ignore[return-value]

    def _active_admins(self, org_id: str) -> int:
        row = self._one("SELECT COUNT(*) AS n FROM instructors WHERE org_id = ? AND role = 'admin' AND disabled = 0", (org_id,))
        return row["n"] if row else 0

    @staticmethod
    def _instructor(row: sqlite3.Row) -> dict:
        return {"id": row["id"], "org_id": row["org_id"], "email": row["email"], "name": row["name"],
                "role": row["role"], "disabled": bool(row["disabled"]), "created_at": row["created_at"]}

    # ---- dashboard sign-in --------------------------------------------------

    def create_login(self, instructor_id: str) -> str:
        token = secrets.token_urlsafe(32)
        self._write("DELETE FROM logins WHERE expires_at < ?", (_now(),))
        self._write("INSERT INTO logins (token_hash, instructor_id, expires_at) VALUES (?, ?, ?)",
                    (_sha(token), instructor_id, _now() + LOGIN_TTL))
        return token

    def instructor_for_login(self, token: str | None) -> dict | None:
        if not token:
            return None
        row = self._one(
            """SELECT i.* FROM logins l JOIN instructors i ON i.id = l.instructor_id
               WHERE l.token_hash = ? AND l.expires_at > ? AND i.disabled = 0""",
            (_sha(token), _now()),
        )
        return self._instructor(row) if row else None

    def end_login(self, token: str | None) -> None:
        if token:
            self._write("DELETE FROM logins WHERE token_hash = ?", (_sha(token),))

    # ---- invites ------------------------------------------------------------

    def create_invite(self, org_id: str, email: str, role: str) -> str:
        email = email.strip().lower()
        if "@" not in email:
            raise StoreError("Enter a valid email address.")
        if role not in ("admin", "instructor"):
            raise StoreError("Role must be admin or instructor.")
        if self._one("SELECT 1 FROM instructors WHERE email = ?", (email,)):
            raise StoreError("An account with that email already exists.")
        token = secrets.token_urlsafe(24)
        self._write("INSERT INTO invites (token_hash, org_id, email, role, expires_at) VALUES (?, ?, ?, ?, ?)",
                    (_sha(token), org_id, email, role, _now() + INVITE_TTL))
        return token

    def peek_invite(self, token: str) -> dict | None:
        row = self._one(
            """SELECT v.email, v.role, o.name AS org_name FROM invites v JOIN orgs o ON o.id = v.org_id
               WHERE v.token_hash = ? AND v.used = 0 AND v.expires_at > ?""", (_sha(token), _now()))
        return dict(row) if row else None

    def accept_invite(self, token: str, name: str, password: str) -> dict:
        with self._lock:
            row = self._one("SELECT * FROM invites WHERE token_hash = ? AND used = 0 AND expires_at > ?", (_sha(token), _now()))
            if row is None:
                raise StoreError("This invite link has expired or was already used. Ask your admin for a new one.")
            instructor = self.create_instructor(row["org_id"], row["email"], name, row["role"], password)
            self._write("UPDATE invites SET used = 1 WHERE token_hash = ?", (_sha(token),))
            return instructor

    # ---- headsets -----------------------------------------------------------

    def create_pairing_code(self, org_id: str) -> dict:
        code = "".join(secrets.choice(PAIRING_ALPHABET) for _ in range(PAIRING_LENGTH))
        expires = _now() + PAIRING_TTL
        self._write("DELETE FROM pairing_codes WHERE expires_at < ?", (_now(),))
        self._write("INSERT INTO pairing_codes (code_hash, org_id, expires_at) VALUES (?, ?, ?)", (_sha(code), org_id, expires))
        return {"code": f"{code[:4]}-{code[4:]}", "expires_at": expires, "expires_in": PAIRING_TTL}

    def redeem_pairing_code(self, code: str, device_name: str) -> tuple[dict, str]:
        """Trade a one-time code for a long-lived headset token. The token is
        returned once and only its hash is kept."""
        with self._lock:
            row = self._one("SELECT * FROM pairing_codes WHERE code_hash = ? AND used = 0 AND expires_at > ?",
                            (_sha(normalize_pairing_code(code)), _now()))
            if row is None:
                raise StoreError("That code isn't valid. Codes last ten minutes and work once; ask for a new one.")
            self._write("UPDATE pairing_codes SET used = 1 WHERE code_hash = ?", (row["code_hash"],))
            token = secrets.token_urlsafe(32)
            device = {"id": _new_id(), "org_id": row["org_id"], "name": (device_name.strip() or "Headset")[:60]}
            self._write("INSERT INTO devices (id, org_id, name, token_hash, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?)",
                        (device["id"], device["org_id"], device["name"], _sha(token), now_iso(), now_iso()))
            return device, token

    def device_for_token(self, token: str | None) -> dict | None:
        if not token:
            return None
        row = self._one("SELECT * FROM devices WHERE token_hash = ? AND revoked = 0", (_sha(token),))
        if row is None:
            return None
        # Record when it was last heard from, at most once a minute.
        last = row["last_seen_at"] or ""
        if not last or datetime.fromisoformat(last) < datetime.now(timezone.utc) - timedelta(minutes=1):
            self._write("UPDATE devices SET last_seen_at = ? WHERE id = ?", (now_iso(), row["id"]))
        return {"id": row["id"], "org_id": row["org_id"], "name": row["name"]}

    def list_devices(self, org_id: str) -> list[dict]:
        rows = self._all("SELECT * FROM devices WHERE org_id = ? AND revoked = 0 ORDER BY name COLLATE NOCASE", (org_id,))
        return [{"id": r["id"], "name": r["name"], "created_at": r["created_at"], "last_seen_at": r["last_seen_at"]} for r in rows]

    def revoke_device(self, org_id: str, device_id: str) -> bool:
        return self._write("UPDATE devices SET revoked = 1 WHERE id = ? AND org_id = ? AND revoked = 0", (device_id, org_id)) > 0

    def rename_device(self, org_id: str, device_id: str, name: str) -> bool:
        name = name.strip()[:60]
        if not name:
            raise StoreError("Give the headset a name.")
        return self._write("UPDATE devices SET name = ? WHERE id = ? AND org_id = ? AND revoked = 0", (name, device_id, org_id)) > 0

    # ---- learners -----------------------------------------------------------

    def add_learner(self, org_id: str, name: str, cohort: str = "", is_demo: bool = False) -> dict:
        """Returns the learner with their PIN. The PIN is shown this once;
        only its hash is kept. An instructor can issue a new one any time."""
        name = name.strip()[:80]
        if not name:
            raise StoreError("A learner needs a name.")
        pin = new_pin()
        learner = {"id": _new_id(), "name": name, "cohort": cohort.strip()[:60], "is_demo": bool(is_demo), "created_at": now_iso()}
        self._write(
            "INSERT INTO learners (id, org_id, name, cohort, is_demo, pin_hash, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (learner["id"], org_id, learner["name"], learner["cohort"], int(is_demo), _hash_pin(pin), learner["created_at"]),
        )
        return {**learner, "pin": pin}

    def reset_pin(self, org_id: str, learner_id: str) -> str:
        pin = new_pin()
        if not self._write("UPDATE learners SET pin_hash = ?, failed_pins = 0, locked_until = 0 WHERE id = ? AND org_id = ?",
                           (_hash_pin(pin), learner_id, org_id)):
            raise StoreError("That learner isn't on your roster.")
        return pin

    def verify_pin(self, org_id: str, learner_id: str, pin: str) -> dict:
        """Check a learner's PIN, with a lockout after repeated wrong tries."""
        row = self._one("SELECT * FROM learners WHERE id = ? AND org_id = ?", (learner_id, org_id))
        if row is None:
            return {"ok": False, "reason": "unknown"}
        now = _now()
        if row["locked_until"] > now:
            return {"ok": False, "reason": "locked", "retry_in": row["locked_until"] - now}
        if _check_pin(pin, row["pin_hash"]):
            self._write("UPDATE learners SET failed_pins = 0 WHERE id = ?", (learner_id,))
            return {"ok": True}
        failures = row["failed_pins"] + 1
        if failures >= PIN_MAX_FAILURES:
            self._write("UPDATE learners SET failed_pins = 0, locked_until = ? WHERE id = ?", (now + PIN_LOCK_SECONDS, learner_id))
            return {"ok": False, "reason": "locked", "retry_in": PIN_LOCK_SECONDS}
        self._write("UPDATE learners SET failed_pins = ? WHERE id = ?", (failures, learner_id))
        return {"ok": False, "reason": "wrong", "attempts_left": PIN_MAX_FAILURES - failures}

    def get_learner(self, org_id: str, learner_id: str) -> dict | None:
        row = self._one("SELECT * FROM learners WHERE id = ? AND org_id = ?", (learner_id, org_id))
        return self._learner(row) if row else None

    def list_learners(self, org_id: str) -> list[dict]:
        rows = self._all("SELECT * FROM learners WHERE org_id = ? ORDER BY cohort, name COLLATE NOCASE", (org_id,))
        return [self._learner(r) for r in rows]

    def delete_learner(self, org_id: str, learner_id: str) -> bool:
        """Erase a learner and every run recorded for them."""
        with self._lock:
            self._db.execute("DELETE FROM sessions WHERE org_id = ? AND learner_id = ?", (org_id, learner_id))
            cur = self._db.execute("DELETE FROM learners WHERE id = ? AND org_id = ?", (learner_id, org_id))
            self._db.commit()
            return cur.rowcount > 0

    def delete_demo_data(self, org_id: str) -> int:
        with self._lock:
            ids = [r["id"] for r in self._db.execute("SELECT id FROM learners WHERE org_id = ? AND is_demo = 1", (org_id,))]
        for learner_id in ids:
            self.delete_learner(org_id, learner_id)
        return len(ids)

    @staticmethod
    def _learner(row: sqlite3.Row) -> dict:
        return {"id": row["id"], "name": row["name"], "cohort": row["cohort"],
                "is_demo": bool(row["is_demo"]), "created_at": row["created_at"],
                "locked": row["locked_until"] > _now()}

    # ---- runs ---------------------------------------------------------------

    def save_session(self, org_id: str, device_id: str | None, record: dict,
                     rubric: dict | None = None, identity: str = "verified") -> dict:
        """Insert or replace one run. The score of record is computed here,
        whatever the headset showed.

        Uploading the same run id twice replaces it, so a headset that retries
        after a dropped connection can't create duplicates. Run ids are scoped
        to the organization: one school can never overwrite another's run.
        """
        learner = self.get_learner(org_id, record["learner_id"]) if record.get("learner_id") else None
        if learner is None:
            raise StoreError("That learner isn't on this school's roster.")

        events = record.get("events") or []
        result = scoring.score_session(record, rubric)
        detail = {
            "result": result,
            "instruments_seen": record.get("instruments_seen") or [],
            "app_version": record.get("app_version") or "",
            "detection_mode": record.get("detection_mode") or "",
        }
        row = (
            org_id, record["id"], learner["id"], learner["name"], device_id, identity,
            record.get("role") or "Trainee", record.get("mode") or "assessed", record.get("headset") or "",
            record["started_at"], record["ended_at"], int(record.get("duration_s") or 0),
            int(bool(record.get("completed"))), int(record.get("stations_completed") or 0),
            sum(1 for e in events if e.get("kind") == "contamination"),
            result["score"], result["verdict"], json.dumps(detail), now_iso(),
        )
        with self._lock:
            self._db.execute("DELETE FROM sessions WHERE org_id = ? AND id = ?", (org_id, record["id"]))
            self._db.execute(
                """INSERT INTO sessions (org_id, id, learner_id, learner_name, device_id, identity, role, mode, headset,
                       started_at, ended_at, duration_s, completed, stations_completed, contamination_count, score,
                       verdict, detail, received_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", row)
            self._db.executemany(
                "INSERT INTO events (org_id, session_id, at, kind, station, message) VALUES (?, ?, ?, ?, ?, ?)",
                [(org_id, record["id"], e.get("at") or record["started_at"], e.get("kind") or "info",
                  e.get("station"), (e.get("message") or "")[:300]) for e in events],
            )
            self._db.commit()
        return self.get_session(org_id, record["id"])  # type: ignore[return-value]

    def get_session(self, org_id: str, session_id: str) -> dict | None:
        row = self._one("SELECT * FROM sessions WHERE org_id = ? AND id = ?", (org_id, session_id))
        if row is None:
            return None
        events = self._all("SELECT at, kind, station, message FROM events WHERE org_id = ? AND session_id = ? ORDER BY seq",
                           (org_id, session_id))
        session = self._session(row)
        session["events"] = [dict(e) for e in events]
        return session

    def list_sessions(self, org_id: str, learner_id: str | None = None, limit: int = 500) -> list[dict]:
        query, args = "SELECT * FROM sessions WHERE org_id = ?", [org_id]
        if learner_id:
            query += " AND learner_id = ?"
            args.append(learner_id)
        query += " ORDER BY started_at DESC LIMIT ?"
        args.append(limit)
        return [self._session(r) for r in self._all(query, tuple(args))]

    def delete_session(self, org_id: str, session_id: str) -> bool:
        return self._write("DELETE FROM sessions WHERE org_id = ? AND id = ?", (org_id, session_id)) > 0

    def purge_older_than(self, days: int) -> int:
        """Retention: remove runs that ended more than `days` ago, in every organization."""
        cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat(timespec="seconds")
        return self._write("DELETE FROM sessions WHERE ended_at < ?", (cutoff,))

    @staticmethod
    def _session(row: sqlite3.Row) -> dict:
        detail = json.loads(row["detail"] or "{}")
        return {
            "id": row["id"], "learner_id": row["learner_id"], "learner_name": row["learner_name"],
            "identity": row["identity"], "role": row["role"], "mode": row["mode"], "headset": row["headset"],
            "started_at": row["started_at"], "ended_at": row["ended_at"], "duration_s": row["duration_s"],
            "completed": bool(row["completed"]), "stations_completed": row["stations_completed"],
            "contamination_count": row["contamination_count"], "score": row["score"], "verdict": row["verdict"],
            "verdict_label": scoring.VERDICT_LABELS.get(row["verdict"], row["verdict"]),
            "result": detail.get("result") or {},
            "instruments_seen": detail.get("instruments_seen") or [],
            "app_version": detail.get("app_version") or "",
            "detection_mode": detail.get("detection_mode") or "",
        }

    # ---- protocol -----------------------------------------------------------

    def get_protocol(self, org_id: str) -> dict | None:
        row = self._one("SELECT * FROM protocols WHERE org_id = ?", (org_id,))
        if row is None:
            return None
        return {**json.loads(row["body"]), "version": row["version"], "updated_at": row["updated_at"],
                "updated_by": row["updated_by"], "is_standard": False}

    def save_protocol(self, org_id: str, body: dict, updated_by: str) -> dict:
        current = self.get_protocol(org_id)
        version = (current["version"] if current else 1) + 1
        with self._lock:
            self._db.execute("DELETE FROM protocols WHERE org_id = ?", (org_id,))
            self._db.execute("INSERT INTO protocols (org_id, body, version, updated_at, updated_by) VALUES (?, ?, ?, ?, ?)",
                             (org_id, json.dumps(body), version, now_iso(), updated_by))
            self._db.commit()
        return self.get_protocol(org_id)  # type: ignore[return-value]

    def delete_protocol(self, org_id: str) -> None:
        self._write("DELETE FROM protocols WHERE org_id = ?", (org_id,))

    # ---- audit --------------------------------------------------------------

    def audit(self, org_id: str, actor: str, action: str, detail: str = "") -> None:
        self._write("INSERT INTO audit (org_id, at, actor, action, detail) VALUES (?, ?, ?, ?, ?)",
                    (org_id, now_iso(), actor[:200], action[:80], detail[:300]))

    def list_audit(self, org_id: str, limit: int = 200) -> list[dict]:
        rows = self._all("SELECT at, actor, action, detail FROM audit WHERE org_id = ? ORDER BY seq DESC LIMIT ?", (org_id, limit))
        return [dict(r) for r in rows]

    # ---- roll-ups for the instructor dashboard ------------------------------

    def overview(self, org_id: str) -> dict:
        learners = self.list_learners(org_id)
        sessions = [s for s in self.list_sessions(org_id, limit=5000) if s["mode"] == "assessed"]
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
                "competent": any(r["verdict"] == scoring.VERDICT_COMPETENT and r["identity"] == "verified" for r in runs),
                "unconfirmed_runs": sum(1 for r in runs if r["identity"] != "verified"),
            })

        # Which station trips people up most — the first thing to re-teach.
        trouble = {key: 0 for key in scoring.STATIONS}
        for s in sessions:
            for st in s["result"].get("stations", []):
                trouble[st["station"]] += st["contamination"] + st["send_back"] + st["count_mismatch"] + st["redo"]
        hardest = max(trouble, key=trouble.get) if any(trouble.values()) else None

        completed = [s for s in sessions if s["completed"]]
        return {
            "learners": len(learners),
            "learners_with_runs": sum(1 for r in roster if r["runs"]),
            "learners_competent": sum(1 for r in roster if r["competent"]),
            "sessions": len(sessions),
            "sessions_completed": len(completed),
            "average_score": round(sum(s["score"] for s in completed) / len(completed)) if completed else None,
            "contamination_events": sum(s["contamination_count"] for s in sessions),
            "station_trouble": [{"station": k, "title": scoring.STATION_TITLES[k], "issues": v} for k, v in trouble.items()],
            "hardest_station": scoring.STATION_TITLES[hardest] if hardest else None,
            "roster": roster,
            "has_demo_data": any(l["is_demo"] for l in learners),
            "headsets": len(self.list_devices(org_id)),
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
