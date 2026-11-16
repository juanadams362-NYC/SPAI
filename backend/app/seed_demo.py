"""
A demo school with a sample cohort, for demos and screenshots.

    python -m app.seed_demo            # create "Demo School" with sample data
    python -m app.seed_demo --clear    # remove the sample learners again

Prints a sign-in for the dashboard and a code to pair a headset. Every
learner it creates is flagged as demo data and labelled "Sample cohort" in
the dashboard — invented people and invented runs, never to be mistaken for
a real class.
"""
from __future__ import annotations

import random
import sys
import uuid
from datetime import datetime, timedelta, timezone

from app import scoring
from app import protocol
from app.store import Store, StoreError, get_store

COHORT = "Sample cohort"
ORG_NAME = "Demo School"
ADMIN_EMAIL = "demo-admin@example.com"
ADMIN_PASSWORD = "demo-password-1"

# (name, starting skill 0..1, how fast they improve per run, number of runs)
LEARNERS = [
    ("Avery Chen", 0.55, 0.12, 6), ("Jordan Okafor", 0.35, 0.10, 7), ("Priya Raman", 0.70, 0.08, 5),
    ("Marcus Bell", 0.25, 0.06, 6), ("Sofia Alvarez", 0.50, 0.14, 5), ("Dee Thompson", 0.40, 0.09, 4),
    ("Noah Fitzgerald", 0.60, 0.05, 3), ("Imani Brooks", 0.45, 0.13, 6), ("Tomas Novak", 0.30, 0.11, 2),
    ("Hana Kimura", 0.65, 0.10, 4), ("Riley Osei", 0.20, 0.07, 1), ("Sam Whitaker", 0.50, 0.00, 0),
]

INSTRUMENTS = ["Adson Dressing Forceps", "Babcock Tissue Forceps", "Halsted Mosquito Forceps",
               "Mayo-Hegar Needle Holder", "Operating Scissors", "Scalpel Handle No. 3"]


def _run(rng: random.Random, skill: float, started: datetime) -> dict:
    """One invented run. Lower skill means more alerts and a higher chance
    of stopping early; the trouble spots mirror where real trainees slip
    (gloves at Inspection, the count at Tray Assembly)."""
    events, clock = [], started
    slip = max(0.03, 0.55 * (1 - skill))

    def log(kind: str, station: str | None, message: str, seconds: float) -> None:
        nonlocal clock
        clock += timedelta(seconds=seconds)
        events.append({"at": clock.isoformat(timespec="seconds"), "kind": kind, "station": station, "message": message})

    done = 0
    for key in scoring.STATIONS:
        title = scoring.STATION_TITLES[key]
        log("station_start", key, f"Started {title}", rng.uniform(8, 30))
        if key in ("decontamination", "inspection") and rng.random() < slip * (1.3 if key == "inspection" else 0.8):
            log("contamination", key, "Contamination detected — workflow halted", rng.uniform(20, 70))
            log("acknowledge", key, "Contamination acknowledged — workflow resumed", rng.uniform(10, 40))
        if rng.random() < slip * 0.5:
            log("redo", key, f"Redo {title}", rng.uniform(30, 80))
        if key == "tray_assembly" and rng.random() < slip * 0.9:
            log("count_mismatch", key, "Count sheet did not match: Halsted Mosquito Forceps missing", rng.uniform(40, 90))
        if key in ("inspection", "tray_assembly") and rng.random() < slip * 0.35:
            log("send_back", key, f"Failed {title} — tray sent back to Decontamination", rng.uniform(30, 60))
        if rng.random() < slip * 0.18:        # ran out of time / gave up
            break
        log("station_complete", key, f"Completed {title}", rng.uniform(90, 240) * (1.5 - skill * 0.6))
        done += 1

    return {
        "id": "demo-" + uuid.uuid4().hex[:16],
        "role": "Trainee", "mode": "assessed", "headset": f"Lab headset {rng.randint(1, 4)}",
        "started_at": started.isoformat(timespec="seconds"), "ended_at": clock.isoformat(timespec="seconds"),
        "duration_s": int((clock - started).total_seconds()),
        "completed": done == len(scoring.STATIONS), "stations_completed": done,
        "events": events, "instruments_seen": rng.sample(INSTRUMENTS, rng.randint(3, 6)),
        "app_version": "demo", "detection_mode": "On-Device",
    }


def demo_org(store: Store) -> dict:
    """The demo school, created with an admin account the first time."""
    for org in store.list_orgs():
        if org["name"] == ORG_NAME:
            return org
    org = store.create_org(ORG_NAME)
    try:
        store.create_instructor(org["id"], ADMIN_EMAIL, "Demo Admin", "admin", ADMIN_PASSWORD)
    except StoreError:
        pass
    return org


def seed(store: Store | None = None, seed_value: int = 7, org_id: str | None = None) -> int:
    store = store or get_store()
    org_id = org_id or demo_org(store)["id"]
    store.delete_demo_data(org_id)
    rng = random.Random(seed_value)
    rubric = protocol.for_org(org_id)["rubric"]
    now = datetime.now(timezone.utc).replace(microsecond=0)
    total = 0
    for name, skill, growth, runs in LEARNERS:
        learner = store.add_learner(org_id, name, COHORT, is_demo=True)
        for i in range(runs):
            # Spread runs over the last six weeks, most recent last.
            started = now - timedelta(days=(runs - i) * rng.uniform(4, 7), hours=rng.uniform(0, 6))
            record = _run(rng, min(0.97, skill + growth * i), started)
            record.update(learner_id=learner["id"])
            store.save_session(org_id, None, record, rubric)
            total += 1
    return total


if __name__ == "__main__":
    store = get_store()
    if "--clear" in sys.argv:
        print(f"Removed {store.delete_demo_data(demo_org(store)['id'])} sample learners.")
    else:
        org = demo_org(store)
        runs = seed(store, org_id=org["id"])
        code = store.create_pairing_code(org["id"])
        print(f"{ORG_NAME}: {len(LEARNERS)} sample learners, {runs} sample runs.")
        print(f"Dashboard sign-in: {ADMIN_EMAIL} / {ADMIN_PASSWORD}  (demo only — change it for anything real)")
        print(f"Headset pairing code (10 minutes): {code['code']}")
