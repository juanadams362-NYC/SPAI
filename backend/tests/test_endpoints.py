"""SCRUM-43 backend tests. Run with: pytest -v"""
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_root_returns_metadata():
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "SPAI Backend"
    assert data["docs"] == "/docs"


def test_health_returns_ok():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_model_status_reports_stub_mode():
    response = client.get("/model/status")
    assert response.status_code == 200
    data = response.json()
    assert data["model_loaded"] is False
    assert data["mode"] == "stub"
    assert "glove" in data["classes"]
    assert "hand" in data["classes"]


def test_detect_returns_stub_detections():
    fake_png = (
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
        b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00"
        b"\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\xf8\x0f"
        b"\x00\x00\x01\x01\x00\x05\xfe\x02\xfe\xdc\xccY\xe7"
        b"\x00\x00\x00\x00IEND\xaeB`\x82"
    )
    response = client.post(
        "/detect",
        files={"image": ("test.png", fake_png, "image/png")},
    )
    assert response.status_code == 200
    data = response.json()
    assert "detections" in data
    assert len(data["detections"]) == 2
    assert data["mode"] == "stub"


def test_detect_rejects_non_image():
    response = client.post(
        "/detect",
        files={"image": ("test.txt", b"not an image", "text/plain")},
    )
    assert response.status_code == 400
