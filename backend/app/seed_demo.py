"""
Fill the dashboard with a sample cohort, for demos and screenshots.

    python -m app.seed_demo            # add the sample cohort
    python -m app.seed_demo --clear    # remove it again

Every learner it creates is flagged as demo data and the dashboard labels
the cohort "Sample data" — these are invented people and invented runs, and
must never be mistaken for a real class. "Remove sample data" in the
dashboard deletes all of it.
"""
from __future__ import annotations

import random
import sys
import uuid
from datetime import datetime, timedelta, timezone

from app import scoring
from app.protocol import get_protocols
from app.store import Store, get_store

COHORT = "Sample cohort"

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


def seed(store: Store | None = None, seed_value: int = 7) -> int:
    store = store or get_store()
    store.delete_demo_data()
    rng = random.Random(seed_value)
    rubric = get_protocols().current()["rubric"]
    now = datetime.now(timezone.utc).replace(microsecond=0)
    total = 0
    for name, skill, growth, runs in LEARNERS:
        learner = store.add_learner(name, COHORT, is_demo=True)
        for i in range(runs):
            # Spread runs over the last six weeks, most recent last.
            started = now - timedelta(days=(runs - i) * rng.uniform(4, 7), hours=rng.uniform(0, 6))
            record = _run(rng, min(0.97, skill + growth * i), started)
            record.update(learner_id=learner["id"], learner_name=name)
            store.save_session(record, rubric)
            total += 1
    return total


if __name__ == "__main__":
    if "--clear" in sys.argv:
        print(f"Removed {get_store().delete_demo_data()} sample learners.")
    else:
        print(f"Added {len(LEARNERS)} sample learners and {seed()} sample runs (cohort: '{COHORT}').")
