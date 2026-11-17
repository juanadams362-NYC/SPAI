"""Pilot platform tests: scoring, runs, PINs, accounts, headsets, protocol.

Run with: pytest -v
"""
from fastapi.testclient import TestClient

from app import scoring, seed_demo
from app.main import app
from app.store import PIN_MAX_FAILURES, get_store
from tests.conftest import ADMIN_PASSWORD


def ev(kind: str, station: str, at: str = "2026-11-12T10:00:00+00:00") -> dict:
    return {"at": at, "kind": kind, "station": station, "message": kind}


def clean_run(learner_id: str, **over) -> dict:
    events = []
    for key in scoring.STATIONS:
        events += [ev("station_start", key), ev("station_complete", key)]
    return {"learner_id": learner_id, "started_at": "2026-11-12T10:00:00+00:00",
            "ended_at": "2026-11-12T10:20:00+00:00", "duration_s": 1200, "completed": True,
            "stations_completed": 5, "events": events, **over}


# --- Scoring -----------------------------------------------------------------

def test_clean_run_is_competent_with_full_marks():
    r = scoring.score_session(clean_run("x"))
    assert (r["score"], r["verdict"]) == (100, "competent")
    assert r["coaching"] == ["Clean run. Every station completed with no alerts."]


def test_one_contamination_fails_competency_even_at_a_passing_score():
    run = clean_run("x")
    run["events"].insert(3, ev("contamination", "inspection"))
    r = scoring.score_session(run)
    assert (r["score"], r["verdict"]) == (80, "needs_practice")


def test_deductions_add_up_and_never_go_below_zero():
    run = clean_run("x")
    run["events"] += [ev("send_back", "tray_assembly"), ev("redo", "packaging"), ev("count_mismatch", "tray_assembly")]
    assert scoring.score_session(run)["score"] == 75
    run["events"] += [ev("contamination", "decontamination")] * 9
    assert scoring.score_session(run)["score"] == 0


def test_unfinished_run_is_incomplete_whatever_the_score():
    r = scoring.score_session({"completed": False, "stations_completed": 2, "events": []})
    assert r["verdict"] == "incomplete" and "Stopped at Tray Assembly" in r["coaching"][-1]


# --- Headsets ----------------------------------------------------------------

def test_unpaired_headset_gets_nothing(client):
    stranger = TestClient(app)
    for method, path in [("get", "/learners"), ("get", "/protocol"), ("get", "/device/me"),
                         ("put", "/sessions/run-0001-abcd"), ("post", "/analyze"), ("get", "/compliance/state")]:
        assert getattr(stranger, method)(path).status_code == 401, path
    forged = TestClient(app, headers={"Authorization": "Bearer not-a-real-token"})
    assert forged.get("/learners").status_code == 401


def test_pairing_code_works_once(admin):
    code = admin.post("/instructor/api/headsets/pairing-code").json()
    assert len(code["code"]) == 9 and code["server"].startswith("http")
    first = TestClient(app).post("/device/pair", json={"code": code["code"].lower().replace("-", " "), "name": "Lab 2"})
    assert first.status_code == 200 and first.json()["organization"]["name"] == "Test School"
    again = TestClient(app).post("/device/pair", json={"code": code["code"], "name": "Lab 3"})
    assert again.status_code == 400


def test_revoked_headset_stops_working_immediately(test_school):
    headsets = test_school.admin.get("/instructor/api/headsets").json()["headsets"]
    assert test_school.headset.get("/device/me").status_code == 200
    assert test_school.admin.delete(f"/instructor/api/headsets/{headsets[0]['id']}").status_code == 200
    assert test_school.headset.get("/learners").status_code == 401


def test_headset_can_disconnect_itself(client):
    assert client.delete("/device/me").json() == {"disconnected": True}
    assert client.get("/device/me").status_code == 401


def test_pairing_is_rate_limited(client):
    from app import security
    security.pairing_limiter.reset()       # the fixture's own pairing used one try
    stranger = TestClient(app)
    codes = [stranger.post("/device/pair", json={"code": f"WRONG{i:03d}"}).status_code for i in range(12)]
    assert codes[:10] == [400] * 10 and codes[-1] == 429


# --- PINs --------------------------------------------------------------------

def test_roster_shows_names_but_never_pins(test_school):
    learner = test_school.add_learner()
    assert len(learner["pin"]) == 4 and learner["pin"].isdigit()
    roster = test_school.headset.get("/learners").json()["learners"]
    assert roster == [{"id": learner["id"], "name": "Avery Chen", "cohort": "Fall A"}]


def test_pin_check_and_lockout(test_school):
    learner = test_school.add_learner()
    url = f"/learners/{learner['id']}/verify-pin"
    wrong = "0000" if learner["pin"] != "0000" else "1111"
    assert test_school.headset.post(url, json={"pin": learner["pin"]}).json() == {"ok": True}
    for left in range(PIN_MAX_FAILURES - 1, 0, -1):
        assert test_school.headset.post(url, json={"pin": wrong}).json() == {"ok": False, "reason": "wrong", "attempts_left": left}
    assert test_school.headset.post(url, json={"pin": wrong}).json()["reason"] == "locked"
    # Locked: even the right PIN is refused until the lock runs out or an instructor resets it.
    assert test_school.headset.post(url, json={"pin": learner["pin"]}).json()["reason"] == "locked"
    new_pin = test_school.admin.post(f"/instructor/api/learners/{learner['id']}/reset-pin").json()["pin"]
    assert test_school.headset.post(url, json={"pin": new_pin}).json() == {"ok": True}
    assert test_school.headset.post(url, json={"pin": "12345"}).status_code == 422


# --- Runs --------------------------------------------------------------------

def test_uploaded_run_is_scored_and_on_the_dashboard(test_school):
    learner = test_school.add_learner()
    saved = test_school.headset.put("/sessions/run-0001-abcd", json=clean_run(learner["id"])).json()
    assert (saved["score"], saved["verdict_label"], saved["identity"]) == (100, "Competent", "verified")
    assert saved["learner_name"] == "Avery Chen"     # the name comes from the roster, not the headset
    detail = test_school.admin.get(f"/instructor/api/learners/{learner['id']}").json()
    assert detail["sessions"][0]["id"] == "run-0001-abcd"


def test_offline_sign_in_is_checked_when_the_run_arrives(test_school):
    learner = test_school.add_learner()
    wrong = "0000" if learner["pin"] != "0000" else "1111"
    good = test_school.headset.put("/sessions/run-offline-01", json=clean_run(learner["id"], pin=learner["pin"])).json()
    bad = test_school.headset.put("/sessions/run-offline-02", json=clean_run(learner["id"], pin=wrong)).json()
    assert (good["identity"], bad["identity"]) == ("verified", "unconfirmed")
    row = test_school.admin.get("/instructor/api/overview").json()["roster"][0]
    assert row["unconfirmed_runs"] == 1
    assert row["competent"]                            # from the verified run only


def test_unconfirmed_runs_never_count_toward_competency(test_school):
    learner = test_school.add_learner()
    wrong = "0000" if learner["pin"] != "0000" else "1111"
    test_school.headset.put("/sessions/run-offline-03", json=clean_run(learner["id"], pin=wrong))
    assert not test_school.admin.get("/instructor/api/overview").json()["roster"][0]["competent"]


def test_runs_need_a_learner_on_the_roster(test_school):
    assert test_school.headset.put("/sessions/run-guest-0001", json=clean_run("nobody")).status_code == 404
    body = clean_run("x")
    del body["learner_id"]
    assert test_school.headset.put("/sessions/run-guest-0002", json=body).status_code == 422
    # Practice runs stay on the headset; the server refuses them.
    learner = test_school.add_learner()
    assert test_school.headset.put("/sessions/run-prac-0001", json=clean_run(learner["id"], mode="practice")).status_code == 422


def test_retried_upload_replaces_rather_than_duplicates(test_school):
    learner = test_school.add_learner()
    for _ in range(3):
        assert test_school.headset.put("/sessions/run-retry-0001", json=clean_run(learner["id"])).status_code == 200
    org = test_school.org["id"]
    assert len(get_store().list_sessions(org)) == 1
    assert len(get_store().get_session(org, "run-retry-0001")["events"]) == 10


def test_deleting_a_learner_erases_their_runs_and_stops_new_ones(test_school):
    learner = test_school.add_learner()
    test_school.headset.put("/sessions/run-erase-0001", json=clean_run(learner["id"]))
    assert test_school.admin.delete(f"/instructor/api/learners/{learner['id']}").json() == {"deleted": True}
    assert get_store().get_session(test_school.org["id"], "run-erase-0001") is None
    # A run that was waiting on the headset gets a clear "stop retrying".
    assert test_school.headset.put("/sessions/run-erase-0002", json=clean_run(learner["id"])).status_code == 404


def test_overview_rolls_up_the_class(test_school):
    a, b = test_school.add_learner("Avery"), test_school.add_learner("Blake")
    test_school.headset.put("/sessions/run-over-00001", json=clean_run(a["id"]))
    rough = clean_run(b["id"])
    rough["events"] += [ev("contamination", "inspection"), ev("contamination", "inspection")]
    test_school.headset.put("/sessions/run-over-00002", json=rough)
    o = test_school.admin.get("/instructor/api/overview").json()
    assert (o["learners"], o["learners_competent"], o["sessions"], o["headsets"]) == (2, 1, 2, 1)
    assert o["hardest_station"] == "Inspection" and o["average_score"] == 80


def test_csv_export_defuses_formulas(test_school):
    learner = test_school.add_learner('=HYPERLINK("evil")')
    test_school.headset.put("/sessions/run-csv-000001", json=clean_run(learner["id"]))
    lines = test_school.admin.get("/instructor/api/export.csv").text.splitlines()
    assert lines[0].startswith("learner,cohort,date") and len(lines) == 2
    assert lines[1].startswith("\"'=HYPERLINK")


def test_retention_purges_old_runs_only(test_school):
    learner = test_school.add_learner()
    test_school.headset.put("/sessions/run-old-000001", json=clean_run(learner["id"], started_at="2020-01-01T10:00:00+00:00", ended_at="2020-01-01T10:20:00+00:00"))
    test_school.headset.put("/sessions/run-new-000001", json=clean_run(learner["id"], started_at="2099-01-01T10:00:00+00:00", ended_at="2099-01-01T10:20:00+00:00"))
    assert get_store().purge_older_than(365) == 1
    assert [s["id"] for s in get_store().list_sessions(test_school.org["id"])] == ["run-new-000001"]


def test_sample_cohort_is_flagged_and_removable(test_school):
    org = test_school.org["id"]
    runs = seed_demo.seed(org_id=org)
    o = test_school.admin.get("/instructor/api/overview").json()
    assert o["has_demo_data"] and o["sessions"] == runs and all(l["is_demo"] for l in o["roster"])
    test_school.admin.delete("/instructor/api/demo")
    assert test_school.admin.get("/instructor/api/overview").json()["learners"] == 0


# --- Instructor accounts -----------------------------------------------------

def test_dashboard_needs_a_sign_in(test_school):
    stranger = TestClient(app)
    assert stranger.get("/instructor").status_code == 200                  # the page loads...
    assert stranger.get("/instructor/api/overview").status_code == 401     # ...its data doesn't
    assert stranger.post("/instructor/login", json={"email": test_school.admin_user["email"], "password": "nope"}).status_code == 401
    assert stranger.post("/instructor/login", json={"email": "nobody@x.edu", "password": ADMIN_PASSWORD}).status_code == 401
    test_school.admin.post("/instructor/logout")
    assert test_school.admin.get("/instructor/api/overview").status_code == 401


def test_sign_in_is_rate_limited(test_school):
    stranger = TestClient(app)
    email = test_school.admin_user["email"]
    codes = [stranger.post("/instructor/login", json={"email": email, "password": "wrong"}).status_code for _ in range(9)]
    assert codes[-1] == 429
    # Even the right password is refused while limited.
    assert stranger.post("/instructor/login", json={"email": email, "password": ADMIN_PASSWORD}).status_code == 429


def test_invite_creates_an_instructor_who_cannot_do_admin_things(test_school):
    link = test_school.admin.post("/instructor/api/team/invite", json={"email": "teacher@school.edu"}).json()["link"]
    token = link.split("#invite/")[1]
    teacher = TestClient(app)
    assert teacher.get(f"/instructor/invite/{token}").json()["org_name"] == "Test School"
    assert teacher.post(f"/instructor/invite/{token}", json={"name": "T", "password": "short"}).status_code == 400
    assert teacher.post(f"/instructor/invite/{token}", json={"name": "Teacher", "password": "a-long-password"}).status_code == 200
    assert TestClient(app).post(f"/instructor/invite/{token}", json={"name": "X", "password": "a-long-password"}).status_code == 400

    learner = test_school.add_learner()
    assert teacher.get("/instructor/api/overview").status_code == 200
    assert teacher.post(f"/instructor/api/learners/{learner['id']}/reset-pin").status_code == 200
    for method, path in [("delete", f"/instructor/api/learners/{learner['id']}"), ("post", "/instructor/api/headsets/pairing-code"),
                         ("put", "/instructor/api/protocol"), ("post", "/instructor/api/team/invite"),
                         ("delete", "/instructor/api/demo"), ("get", "/instructor/api/activity")]:
        assert getattr(teacher, method)(path, **({"json": {}} if method in ("put", "post") else {})).status_code in (403, 422), path


def test_removed_instructor_is_signed_out_everywhere(test_school):
    link = test_school.admin.post("/instructor/api/team/invite", json={"email": "leaver@school.edu"}).json()["link"]
    leaver = TestClient(app)
    leaver.post(f"/instructor/invite/{link.split('#invite/')[1]}", json={"name": "Leaver", "password": "a-long-password"})
    member = next(m for m in test_school.admin.get("/instructor/api/team").json()["instructors"] if m["email"] == "leaver@school.edu")
    test_school.admin.patch(f"/instructor/api/team/{member['id']}", json={"disabled": True})
    assert leaver.get("/instructor/api/overview").status_code == 401
    assert TestClient(app).post("/instructor/login", json={"email": "leaver@school.edu", "password": "a-long-password"}).status_code == 401


def test_last_admin_cannot_be_removed(test_school):
    me = test_school.admin_user["id"]
    assert test_school.admin.patch(f"/instructor/api/team/{me}", json={"disabled": True}).status_code == 400
    assert test_school.admin.patch(f"/instructor/api/team/{me}", json={"role": "instructor"}).status_code == 400


def test_password_change_signs_out_other_browsers(test_school):
    other = TestClient(app)
    other.post("/instructor/login", json={"email": test_school.admin_user["email"], "password": ADMIN_PASSWORD})
    r = test_school.admin.post("/instructor/api/account/password", json={"current": ADMIN_PASSWORD, "new": "a-brand-new-password"})
    assert r.status_code == 200
    assert other.get("/instructor/api/overview").status_code == 401
    assert test_school.admin.get("/instructor/api/overview").status_code == 200


def test_cross_site_requests_are_refused(test_school):
    learner = test_school.add_learner()
    r = test_school.admin.delete(f"/instructor/api/learners/{learner['id']}", headers={"Origin": "https://evil.example"})
    assert r.status_code == 403
    assert test_school.admin.get(f"/instructor/api/learners/{learner['id']}").status_code == 200


def test_actions_are_written_to_the_activity_log(test_school):
    learner = test_school.add_learner()
    test_school.admin.post(f"/instructor/api/learners/{learner['id']}/reset-pin")
    actions = [e["action"] for e in test_school.admin.get("/instructor/api/activity").json()["events"]]
    assert "issued a new PIN" in actions and "added learners" in actions and "headset paired" in actions


# --- Per-headset workflow ----------------------------------------------------

def test_two_runs_on_one_headset_do_not_share_workflow_state(client):
    a, b = {"X-SPAI-Session": "run-a"}, {"X-SPAI-Session": "run-b"}
    start = {"event": "start_step", "step": "decontamination"}
    assert client.post("/compliance/event", json=start, headers=a).json()["accepted"]
    client.post("/compliance/event", json={"event": "contamination"}, headers=a)
    assert client.get("/compliance/state", headers=a).json()["state"] == "halted"
    assert client.get("/compliance/state", headers=b).json()["state"] == "not_started"


# --- Protocol ----------------------------------------------------------------

def test_standard_protocol_until_a_school_edits_its_own(test_school):
    p = test_school.headset.get("/protocol").json()
    assert p["is_standard"] and [s["key"] for s in p["stations"]] == scoring.STATIONS
    edited = test_school.admin.get("/instructor/api/protocol").json()
    edited["stations"][0]["steps"][0]["instruction"] = "Our school: gown, face shield, and double gloves."
    saved = test_school.admin.put("/instructor/api/protocol", json=edited)
    assert saved.status_code == 200 and saved.json()["version"] == 2
    assert test_school.headset.get("/protocol").json()["stations"][0]["steps"][0]["instruction"].startswith("Our school")
    assert test_school.admin.post("/instructor/api/protocol/reset").json()["is_standard"]


def test_broken_protocol_is_refused_with_a_reason(test_school):
    p = test_school.admin.get("/instructor/api/protocol").json()
    p["stations"].pop()
    r = test_school.admin.put("/instructor/api/protocol", json=p)
    assert r.status_code == 422 and "Seal Validation station is missing" in r.json()["detail"]
    assert test_school.headset.get("/protocol").json()["is_standard"]
