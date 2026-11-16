"""Shared test fixtures.

Every test gets its own empty database. `client` is a paired headset in
"Test School"; `admin` is that school's signed-in admin. Use `school()` to
make a second, separate school when a test needs to prove isolation.
"""
import pytest
from fastapi.testclient import TestClient

from app import security, store
from app.main import app

ADMIN_PASSWORD = "correct-horse-battery"


@pytest.fixture(autouse=True)
def isolated_data(tmp_path, monkeypatch):
    monkeypatch.delenv("SPAI_RETENTION_DAYS", raising=False)
    monkeypatch.delenv("SPAI_OPERATOR_KEY", raising=False)
    store.use_store(store.Store(tmp_path / "test.db"))
    for limiter in (security.login_limiter, security.pairing_limiter, security.pin_limiter):
        limiter.reset()
    yield
    store.get_store().close()
    store.use_store(None)


class School:
    """One organization with a signed-in admin and a paired headset."""

    def __init__(self, name: str, admin_email: str):
        s = store.get_store()
        self.org = s.create_org(name)
        self.admin_user = s.create_instructor(self.org["id"], admin_email, "Admin " + name, "admin", ADMIN_PASSWORD)
        self.admin = TestClient(app)
        assert self.admin.post("/instructor/login", json={"email": admin_email, "password": ADMIN_PASSWORD}).status_code == 200
        code = self.admin.post("/instructor/api/headsets/pairing-code").json()["code"]
        paired = TestClient(app).post("/device/pair", json={"code": code, "name": "Lab headset 1"}).json()
        self.token = paired["token"]
        self.headset = TestClient(app, headers={"Authorization": f"Bearer {self.token}"})

    def add_learner(self, name: str = "Avery Chen", cohort: str = "Fall A") -> dict:
        return self.admin.post("/instructor/api/learners", json={"names": [name], "cohort": cohort}).json()["added"][0]


@pytest.fixture
def school():
    made = []

    def make(name: str = "Test School", admin_email: str | None = None) -> School:
        made.append(School(name, admin_email or f"admin{len(made)}@school{len(made)}.edu"))
        return made[-1]
    return make


@pytest.fixture
def test_school(school) -> School:
    return school()


@pytest.fixture
def client(test_school) -> TestClient:
    """A paired headset, for tests of the detection and reference routes."""
    return test_school.headset


@pytest.fixture
def admin(test_school) -> TestClient:
    return test_school.admin
