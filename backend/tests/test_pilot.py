"""Pilot platform tests: scoring, records, per-headset state, access, protocol.

Run with: pytest -v
"""
from fastapi.testclient import TestClient

from app import scoring, seed_demo
from app.main import app
from app.store import get_store

client = TestClient(app)


def ev(kind: str, station: str, at: str = "2026-11-12T10:00:00+00:00") -> dict:
    return {"at": at, "kind": kind, "station": station, "message": kind}


def clean_run(**over) -> dict:
    events = []
    for key in scoring.STATIONS:
        events += [ev("station_start", key), ev("station_complete", key)]
    return {"learner_name": "Avery Chen", "started_at": "2026-11-12T10:00:00+00:00",
            "ended_at": "2026-11-12T10:20:00+00:00", "duration_s": 1200, "completed": True,
            "stations_completed": 5, "events": events, **over}


# --- Scoring -----------------------------------------------------------------

def test_clean_run_is_competent_with_full_marks():
    r = scoring.score_session(clean_run())
    assert (r["score"], r["verdict"]) == (100, "competent")
    assert all(s["clean"] for s in r["stations"])
    assert r["coaching"] == ["Clean run. Every station completed with no alerts."]


def test_one_contamination_fails_competency_even_at_a_passing_score():
    run = clean_run()
    run["events"].insert(3, ev("contamination", "inspection"))
    r = scoring.score_session(run)
    assert r["score"] == 80                      # at the pass mark...
    assert r["verdict"] == "needs_practice"      # ...but contamination is a hard stop
    assert any("Inspection" in note for note in r["coaching"])


def test_deductions_add_up_and_never_go_below_zero():
    run = clean_run()
    run["events"] += [ev("send_back", "tray_assembly"), ev("redo", "packaging"), ev("count_mismatch", "tray_assembly")]
    r = scoring.score_session(run)
    assert r["score"] == 100 - 10 - 5 - 10
    assert {d["reason"] for d in r["deductions"]} == {"Tray sent back", "Station redone", "Count sheet mismatch"}
    run["events"] += [ev("contamination", "decontamination")] * 9
    assert scoring.score_session(run)["score"] == 0


def test_unfinished_run_is_incomplete_whatever_the_score():
    r = scoring.score_session({"completed": False, "stations_completed": 2, "events": []})
    assert r["verdict"] == "incomplete"
    assert "Stopped at Tray Assembly" in r["coaching"][-1]


def test_institution_rubric_changes_the_verdict():
    run = clean_run()
    run["events"].append(ev("redo", "packaging"))
    assert scoring.score_session(run)["verdict"] == "competent"
    assert scoring.score_session(run, {"redo_penalty": 30})["verdict"] == "needs_practice"


# --- Records -----------------------------------------------------------------

def test_uploaded_run_is_scored_by_the_server_and_retrievable():
    learner = client.post("/instructor/api/learners", json={"names": ["Avery Chen"], "cohort": "Fall A"}).json()["added"][0]
    saved = client.put("/sessions/run-0001-abcd", json=clean_run(learner_id=learner["id"])).json()
    assert saved["score"] == 100 and saved["verdict_label"] == "Competent"
    detail = client.get("/instructor/api/sessions/run-0001-abcd").json()
    assert len(detail["events"]) == 10
    assert client.get(f"/instructor/api/learners/{learner['id']}").json()["sessions"][0]["id"] == "run-0001-abcd"


def test_retried_upload_replaces_rather_than_duplicates():
    for _ in range(3):
        assert client.put("/sessions/run-retry-0001", json=clean_run()).status_code == 200
    assert len(get_store().list_sessions()) == 1
    assert len(get_store().get_session("run-retry-0001")["events"]) == 10


def test_bad_uploads_are_rejected():
    assert client.put("/sessions/short", json=clean_run()).status_code == 400
    assert client.put("/sessions/run-bad-00001", json=clean_run(mode="exam")).status_code == 422
    assert client.put("/sessions/run-bad-00002", json={"learner_name": "x"}).status_code == 422


def test_deleting_a_learner_erases_all_their_runs():
    learner = client.post("/instructor/api/learners", json={"names": ["Jordan Okafor"]}).json()["added"][0]
    client.put("/sessions/run-erase-0001", json=clean_run(learner_id=learner["id"]))
    assert client.delete(f"/instructor/api/learners/{learner['id']}").json() == {"deleted": True}
    assert get_store().get_session("run-erase-0001") is None
    assert client.get("/learners").json()["learners"] == []
    assert client.delete(f"/instructor/api/learners/{learner['id']}").status_code == 404


def test_overview_rolls_up_the_class():
    a, b = client.post("/instructor/api/learners", json={"names": ["Avery", "Blake"], "cohort": "A"}).json()["added"]
    client.put("/sessions/run-over-00001", json=clean_run(learner_id=a["id"]))
    rough = clean_run(learner_id=b["id"])
    rough["events"] += [ev("contamination", "inspection"), ev("contamination", "inspection")]
    client.put("/sessions/run-over-00002", json=rough)
    client.put("/sessions/run-over-00003", json=clean_run(learner_id=b["id"], mode="practice"))  # practice doesn't count
    o = client.get("/instructor/api/overview").json()
    assert (o["learners"], o["learners_competent"], o["sessions"]) == (2, 1, 2)
    assert o["hardest_station"] == "Inspection" and o["contamination_events"] == 2
    assert o["average_score"] == 80


def test_csv_export_has_one_row_per_run_and_defuses_formulas():
    client.put("/sessions/run-csv-000001", json=clean_run(learner_name="=HYPERLINK(\"evil\")"))
    body = client.get("/instructor/api/export.csv").text.splitlines()
    assert body[0].startswith("learner,cohort,date") and len(body) == 2
    assert body[1].startswith("\"'=HYPERLINK")


def test_retention_purges_old_runs_only():
    client.put("/sessions/run-old-000001", json=clean_run(started_at="2020-01-01T10:00:00+00:00", ended_at="2020-01-01T10:20:00+00:00"))
    client.put("/sessions/run-new-000001", json=clean_run(started_at="2099-01-01T10:00:00+00:00", ended_at="2099-01-01T10:20:00+00:00"))
    assert get_store().purge_older_than(365) == 1
    assert [s["id"] for s in get_store().list_sessions()] == ["run-new-000001"]


def test_sample_cohort_is_flagged_and_removable():
    runs = seed_demo.seed()
    o = client.get("/instructor/api/overview").json()
    assert o["has_demo_data"] and o["learners"] == len(seed_demo.LEARNERS) and o["sessions"] == runs
    assert all(l["is_demo"] for l in o["roster"])
    client.delete("/instructor/api/demo")
    assert client.get("/instructor/api/overview").json()["learners"] == 0


# --- One workflow per headset ------------------------------------------------

def test_two_headsets_do_not_share_workflow_state():
    a, b = {"X-SPAI-Session": "headset-a"}, {"X-SPAI-Session": "headset-b"}
    start = {"event": "start_step", "step": "decontamination"}
    assert client.post("/compliance/event", json=start, headers=a).json()["accepted"]
    client.post("/compliance/event", json={"event": "contamination"}, headers=a)
    assert client.get("/compliance/state", headers=a).json()["state"] == "halted"
    # B is untouched by A's halt and can start its own run.
    assert client.get("/compliance/state", headers=b).json()["state"] == "not_started"
    assert client.post("/compliance/event", json=start, headers=b).json()["accepted"]
    # Resetting B leaves A halted.
    client.post("/compliance/reset", headers=b)
    assert client.get("/compliance/state", headers=a).json()["state"] == "halted"


# --- Access ------------------------------------------------------------------

def test_headset_routes_need_the_key_once_one_is_set(monkeypatch):
    monkeypatch.setenv("SPAI_API_KEY", "site-key")
    assert client.get("/learners").status_code == 401
    assert client.put("/sessions/run-key-000001", json=clean_run()).status_code == 401
    assert client.get("/learners", headers={"X-SPAI-Key": "wrong"}).status_code == 401
    assert client.get("/learners", headers={"X-SPAI-Key": "site-key"}).status_code == 200
    assert client.get("/health").status_code == 200          # liveness stays open
    assert client.get("/privacy").status_code == 200         # so does the privacy statement


def test_dashboard_needs_the_pin_once_one_is_set(monkeypatch):
    monkeypatch.setenv("SPAI_INSTRUCTOR_PIN", "4321")
    fresh = TestClient(app)
    assert fresh.get("/instructor").status_code == 200                      # the page itself loads...
    assert fresh.get("/instructor/api/overview").status_code == 401         # ...its data doesn't
    assert fresh.post("/instructor/login", json={"pin": "0000"}).status_code == 401
    assert fresh.post("/instructor/login", json={"pin": "4321"}).status_code == 200
    assert fresh.get("/instructor/api/overview").status_code == 200
    fresh.post("/instructor/logout")
    assert fresh.get("/instructor/api/overview").status_code == 401


# --- Protocol ----------------------------------------------------------------

def test_standard_protocol_covers_five_stations_and_a_count_sheet():
    p = client.get("/protocol").json()
    assert [s["key"] for s in p["stations"]] == scoring.STATIONS and p["is_standard"]
    assert len(p["count_sheets"][0]["items"]) == 6
    assert any(step["condition"] == "count_matches" for step in p["stations"][2]["steps"])


def test_instructor_edit_reaches_headsets_and_ask_spai():
    from app.ask_spai import build_context
    p = client.get("/protocol").json()
    p["stations"][0]["steps"][0]["instruction"] = "Our school: gown, face shield, and double gloves."
    saved = client.put("/instructor/api/protocol", json=p)
    assert saved.status_code == 200 and saved.json()["version"] == 2 and not saved.json()["is_standard"]
    assert client.get("/protocol").json()["stations"][0]["steps"][0]["instruction"].startswith("Our school")
    assert "Our school: gown" in build_context("decontamination", 0, "", "what do I wear?")
    assert client.post("/instructor/api/protocol/reset").json()["is_standard"]


def test_broken_protocol_is_refused_with_a_reason():
    p = client.get("/protocol").json()
    p["stations"].pop()
    r = client.put("/instructor/api/protocol", json=p)
    assert r.status_code == 422 and "Seal Validation station is missing" in r.json()["detail"]
    p = client.get("/protocol").json()
    p["stations"][1]["steps"][0]["instruction"] = "   "
    assert "has no instruction" in client.put("/instructor/api/protocol", json=p).json()["detail"]
    p = client.get("/protocol").json()
    p["count_sheets"][0]["items"] = [{"key": "banana", "count": 1}]
    assert "can't recognise" in client.put("/instructor/api/protocol", json=p).json()["detail"]
    assert client.get("/protocol").json()["is_standard"]      # nothing went live
