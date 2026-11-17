"""
Competency scoring.

Turns one session's record into the three things an instructor needs: a
score, a verdict, and what to coach. The rubric is deliberately simple and
fully explainable — every point lost is tied to a named event, so a student
can be told exactly why they got the result they did.

Pure functions, no I/O. The visionOS app carries the same rubric
(Competency.swift) so a student sees a result even when the headset is
offline; the server's score is the one of record.
"""
from __future__ import annotations

STATIONS = ["decontamination", "inspection", "tray_assembly", "packaging", "seal_validation"]

STATION_TITLES = {
    "decontamination": "Decontamination",
    "inspection": "Inspection",
    "tray_assembly": "Tray Assembly",
    "packaging": "Packaging",
    "seal_validation": "Seal Validation",
}

# Points lost per event. Editable per institution through the protocol.
DEFAULT_RUBRIC = {
    "contamination_penalty": 20,   # bare hand where gloves are required
    "send_back_penalty": 10,       # tray failed and went back to decontamination
    "redo_penalty": 5,             # a station restarted
    "count_mismatch_penalty": 10,  # tray closed with the count sheet not matching
    "pass_score": 80,
    # A contamination event is a hard stop for competency however good the
    # rest of the run was: the point of the exercise is that it never happens.
    "max_contaminations_to_pass": 0,
}

VERDICT_COMPETENT = "competent"
VERDICT_NEEDS_PRACTICE = "needs_practice"
VERDICT_INCOMPLETE = "incomplete"

VERDICT_LABELS = {
    VERDICT_COMPETENT: "Competent",
    VERDICT_NEEDS_PRACTICE: "Needs practice",
    VERDICT_INCOMPLETE: "Incomplete",
}


def _count(events: list[dict], kind: str, station: str | None = None) -> int:
    return sum(1 for e in events if e.get("kind") == kind and (station is None or e.get("station") == station))


def score_session(session: dict, rubric: dict | None = None) -> dict:
    """Score one session.

    `session` needs: completed (bool), stations_completed (int), and events —
    a list of {kind, station}. Event kinds that affect the score:
    contamination, send_back, redo, count_mismatch.
    """
    r = {**DEFAULT_RUBRIC, **(rubric or {})}
    events = session.get("events") or []

    contaminations = _count(events, "contamination")
    send_backs = _count(events, "send_back")
    redos = _count(events, "redo")
    mismatches = _count(events, "count_mismatch")

    deductions = []
    if contaminations:
        deductions.append({"reason": "Contamination", "count": contaminations,
                           "points": contaminations * r["contamination_penalty"]})
    if send_backs:
        deductions.append({"reason": "Tray sent back", "count": send_backs,
                           "points": send_backs * r["send_back_penalty"]})
    if redos:
        deductions.append({"reason": "Station redone", "count": redos,
                           "points": redos * r["redo_penalty"]})
    if mismatches:
        deductions.append({"reason": "Count sheet mismatch", "count": mismatches,
                           "points": mismatches * r["count_mismatch_penalty"]})

    score = max(0, 100 - sum(d["points"] for d in deductions))
    completed = bool(session.get("completed"))

    if not completed:
        verdict = VERDICT_INCOMPLETE
    elif score >= r["pass_score"] and contaminations <= r["max_contaminations_to_pass"]:
        verdict = VERDICT_COMPETENT
    else:
        verdict = VERDICT_NEEDS_PRACTICE

    per_station = []
    for key in STATIONS:
        issues = {
            "contamination": _count(events, "contamination", key),
            "send_back": _count(events, "send_back", key),
            "redo": _count(events, "redo", key),
            "count_mismatch": _count(events, "count_mismatch", key),
        }
        done = _count(events, "station_complete", key) > 0
        per_station.append({
            "station": key,
            "title": STATION_TITLES[key],
            "completed": done,
            "clean": done and not any(issues.values()),
            **issues,
        })

    return {
        "score": score,
        "verdict": verdict,
        "verdict_label": VERDICT_LABELS[verdict],
        "deductions": deductions,
        "stations": per_station,
        "coaching": coaching_notes(per_station, completed, session.get("stations_completed", 0)),
    }


def coaching_notes(per_station: list[dict], completed: bool, stations_completed: int) -> list[str]:
    """Plain-language pointers for the instructor's next conversation."""
    notes = []
    for s in per_station:
        if s["contamination"]:
            times = "once" if s["contamination"] == 1 else f"{s['contamination']} times"
            notes.append(f"Bare hand detected {times} at {s['title']}. Review glove checks before handling instruments there.")
        if s["send_back"]:
            notes.append(f"Tray was sent back from {s['title']}. Walk through what failed and how to catch it a station earlier.")
        if s["count_mismatch"]:
            notes.append(f"Count sheet did not match at {s['title']}. Practise counting against the sheet before closing the tray.")
        if s["redo"] >= 2:
            notes.append(f"{s['title']} was restarted {s['redo']} times. The steps there may need another demonstration.")
    if not completed:
        nxt = STATION_TITLES[STATIONS[min(stations_completed, len(STATIONS) - 1)]]
        notes.append(f"Run ended before finishing. Stopped at {nxt}.")
    if not notes:
        notes.append("Clean run. Every station completed with no alerts.")
    return notes
