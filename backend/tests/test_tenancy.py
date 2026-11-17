"""School A must never see or change anything belonging to school B.

Each test sets up two schools, then has one try to reach the other's data
through every door: its headset, its instructors, guessed ids.
"""
from fastapi.testclient import TestClient

from app.main import app
from app.store import get_store
from tests.test_pilot import clean_run


def test_rosters_are_separate(school):
    a, b = school("School A"), school("School B")
    a.add_learner("Only In A")
    b.add_learner("Only In B")
    assert [l["name"] for l in a.headset.get("/learners").json()["learners"]] == ["Only In A"]
    assert [l["name"] for l in b.headset.get("/learners").json()["learners"]] == ["Only In B"]
    assert [r["name"] for r in a.admin.get("/instructor/api/overview").json()["roster"]] == ["Only In A"]


def test_headset_cannot_sign_in_or_upload_as_another_schools_learner(school):
    a, b = school("School A"), school("School B")
    theirs = b.add_learner()
    assert a.headset.post(f"/learners/{theirs['id']}/verify-pin", json={"pin": theirs["pin"]}).status_code == 404
    assert a.headset.put("/sessions/run-cross-0001", json=clean_run(theirs["id"])).status_code == 404
    assert get_store().list_sessions(b.org["id"]) == []


def test_same_run_id_in_two_schools_does_not_collide(school):
    a, b = school("School A"), school("School B")
    la, lb = a.add_learner("A"), b.add_learner("B")
    a.headset.put("/sessions/run-same-00001", json=clean_run(la["id"]))
    b.headset.put("/sessions/run-same-00001", json=clean_run(lb["id"]))
    assert get_store().get_session(a.org["id"], "run-same-00001")["learner_name"] == "A"
    assert get_store().get_session(b.org["id"], "run-same-00001")["learner_name"] == "B"


def test_instructor_cannot_read_or_change_another_schools_records(school):
    a, b = school("School A"), school("School B")
    theirs = b.add_learner()
    b.headset.put("/sessions/run-theirs-0001", json=clean_run(theirs["id"]))
    headset_b = b.admin.get("/instructor/api/headsets").json()["headsets"][0]["id"]
    admin_b = b.admin_user["id"]
    for method, path in [
        ("get", f"/instructor/api/learners/{theirs['id']}"),
        ("get", f"/instructor/api/learners/{theirs['id']}/export"),
        ("post", f"/instructor/api/learners/{theirs['id']}/reset-pin"),
        ("delete", f"/instructor/api/learners/{theirs['id']}"),
        ("get", "/instructor/api/sessions/run-theirs-0001"),
        ("delete", "/instructor/api/sessions/run-theirs-0001"),
        ("delete", f"/instructor/api/headsets/{headset_b}"),
    ]:
        assert getattr(a.admin, method)(path).status_code == 404, path
    assert a.admin.patch(f"/instructor/api/team/{admin_b}", json={"disabled": True}).status_code == 404
    # Nothing of B's changed.
    assert b.headset.get("/device/me").status_code == 200
    assert get_store().get_session(b.org["id"], "run-theirs-0001") is not None
    assert len(b.admin.get("/instructor/api/team").json()["instructors"]) == 1


def test_csv_export_and_activity_log_are_per_school(school):
    a, b = school("School A"), school("School B")
    lb = b.add_learner("Secret B Student")
    b.headset.put("/sessions/run-b-csv-0001", json=clean_run(lb["id"]))
    assert "Secret B Student" not in a.admin.get("/instructor/api/export.csv").text
    assert all("Secret B" not in e["detail"] for e in a.admin.get("/instructor/api/activity").json()["events"])


def test_protocols_are_per_school(school):
    a, b = school("School A"), school("School B")
    p = a.admin.get("/instructor/api/protocol").json()
    p["stations"][0]["steps"][0]["instruction"] = "School A wording."
    a.admin.put("/instructor/api/protocol", json=p)
    assert a.headset.get("/protocol").json()["stations"][0]["steps"][0]["instruction"] == "School A wording."
    assert b.headset.get("/protocol").json()["is_standard"]


def test_pairing_code_joins_the_school_that_made_it(school):
    a, b = school("School A"), school("School B")
    code = b.admin.post("/instructor/api/headsets/pairing-code").json()["code"]
    paired = TestClient(app).post("/device/pair", json={"code": code, "name": "New"}).json()
    assert paired["organization"]["name"] == "School B"
    assert len(b.admin.get("/instructor/api/headsets").json()["headsets"]) == 2
    assert len(a.admin.get("/instructor/api/headsets").json()["headsets"]) == 1


def test_one_email_belongs_to_one_school(school):
    a, b = school("School A"), school("School B")
    r = b.admin.post("/instructor/api/team/invite", json={"email": a.admin_user["email"]})
    assert r.status_code == 400
