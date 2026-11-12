"""Instrument identification tests — catalog, held/focus rule, and endpoints.

Run with: pytest -v
"""
from fastapi.testclient import TestClient

from app import instruments
from app.ask_spai import build_context
from app.inference.detector import Detector
from app.inference.tray_detector import tray_detector
from app.main import app

client = TestClient(app)

TINY_PNG = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
    b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00"
    b"\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\xf8\x0f"
    b"\x00\x00\x01\x01\x00\x05\xfe\x02\xfe\xdc\xccY\xe7"
    b"\x00\x00\x00\x00IEND\xaeB`\x82"
)

# The label list baked into backend/model/instruments_best.pt.
MODEL_LABELS = [
    "Adson Dressing Forceps",
    "Babcock Tissue Forceps",
    "Halsted Mosquito Forceps",
    "Mayo Hegar Needle Holder",
    "Operating Scissors",
    "Scalpel Handle 3",
]


def det(name: str, confidence: float, box: list[int], held: bool | None = None) -> dict:
    d = {"class_id": 0, "class_name": name, "confidence": confidence, "box": box}
    if held is not None:
        d["held"] = held
    return d


# --- Catalog -----------------------------------------------------------------

def test_every_model_label_has_a_reference_card():
    for label in MODEL_LABELS:
        info = instruments.lookup(label)
        assert info is not None, f"no catalog entry for model label {label!r}"
        assert info.summary and info.spoken and info.inspect


def test_lookup_tolerates_spelling_and_case():
    expected = "mayo_hegar_needle_holder"
    for label in ("Mayo Hegar Needle Holder", "mayo-hegar needle holder", " MAYO_HEGAR_NEEDLE_HOLDER ", "needle holder"):
        assert instruments.lookup(label).key == expected


def test_unknown_label_falls_back_to_itself():
    assert instruments.lookup("Kelly Clamp") is None
    assert instruments.display_name("Kelly Clamp") == "Kelly Clamp"
    assert instruments.display_name("") == "instrument"


# --- Held / focus rule -------------------------------------------------------

def test_instrument_touching_a_glove_is_held():
    found = [det("Operating Scissors", 0.8, [100, 100, 200, 200]),
             det("Scalpel Handle 3", 0.8, [600, 600, 700, 700])]
    hands = [det("glove", 0.9, [190, 150, 320, 300])]
    instruments.mark_held(found, hands)
    assert found[0]["held"] is True
    assert found[1]["held"] is False


def test_held_instrument_wins_over_a_more_confident_one_on_the_bench():
    found = [det("Operating Scissors", 0.95, [0, 0, 50, 50], held=False),
             det("Mayo Hegar Needle Holder", 0.70, [100, 100, 200, 200], held=True)]
    result = instruments.identify(found)
    assert result["key"] == "mayo_hegar_needle_holder"
    assert result["name"] == "Mayo-Hegar Needle Holder"
    assert result["certain"] is True
    assert result["held"] is True
    assert result["info"]["category"] == "Needle holder"


def test_low_confidence_is_not_named():
    result = instruments.identify([det("Operating Scissors", 0.30, [0, 0, 50, 50])])
    assert result["certain"] is False
    assert result["key"] == "instrument"
    assert result["info"] is None
    assert "not sure" in result["spoken"]


def test_threshold_is_respected():
    found = [det("Operating Scissors", 0.60, [0, 0, 50, 50])]
    assert instruments.identify(found, threshold=0.5)["certain"] is True
    assert instruments.identify(found, threshold=0.7)["certain"] is False


def test_nothing_in_frame_identifies_nothing():
    assert instruments.identify([]) is None


# --- Detector labelling ------------------------------------------------------

def test_detector_reads_names_from_the_model_not_a_hardcoded_list():
    class FakeModel:
        names = {i: n for i, n in enumerate(MODEL_LABELS)}

    d = Detector()
    d.model = FakeModel()
    d.class_names = d._names_from_model()
    assert d.label(3) == "Mayo Hegar Needle Holder"
    assert d.label(0) != "glove"      # the old bug: instrument ids named with PPE labels
    assert d.label(99) == "99"


# --- Endpoints (stub mode) ---------------------------------------------------

def test_instruments_endpoint_lists_all_six():
    data = client.get("/instruments").json()
    assert data["count"] == 6
    assert {i["key"] for i in data["instruments"]} == {instruments.key_for(l) for l in MODEL_LABELS}


def test_instrument_card_by_key_and_unknown():
    assert client.get("/instruments/operating_scissors").json()["name"] == "Operating Scissors"
    assert client.get("/instruments/banana").status_code == 404


def test_detect_tray_names_the_instrument():
    data = client.post("/detect-tray", files={"image": ("t.png", TINY_PNG, "image/png")}).json()
    assert data["tray_state"] == "loaded"
    assert data["instrument_count"] == 1
    first = data["detections"][0]
    assert first["class_name"] == "Mayo-Hegar Needle Holder"
    assert first["key"] == "mayo_hegar_needle_holder"
    assert first["category"] == "instrument"
    assert data["identified"]["certain"] is True


def test_analyze_returns_ppe_instruments_and_identification():
    response = client.post("/analyze", files={"image": ("t.png", TINY_PNG, "image/png")})
    assert response.status_code == 200
    data = response.json()
    assert {d["class_name"] for d in data["detections"]} == {"glove", "hand"}
    assert data["instrument_count"] == 1
    assert data["tray_state"] == "loaded"
    # Stub glove box overlaps the stub instrument box, so it reads as held.
    assert data["instruments"][0]["held"] is True
    assert data["identified"]["name"] == "Mayo-Hegar Needle Holder"
    assert data["identified"]["held"] is True
    assert data["mode"] == "stub"


def test_analyze_rejects_non_image_and_empty_upload():
    assert client.post("/analyze", files={"image": ("t.txt", b"nope", "text/plain")}).status_code == 400
    assert client.post("/analyze", files={"image": ("t.png", b"", "image/png")}).status_code == 400


def test_settings_expose_and_update_identify_threshold():
    original = tray_detector.identify_threshold
    try:
        data = client.patch("/settings", json={"identify_threshold": 0.8}).json()
        assert data["identify_threshold"] == 0.8
        assert client.get("/settings").json()["identify_threshold"] == 0.8
        assert client.patch("/settings", json={"identify_threshold": 1.5}).status_code == 422
    finally:
        tray_detector.identify_threshold = original


def test_detections_are_counted_in_metrics():
    before = client.get("/health/stats").json()["metrics"]["detection_count"]
    client.post("/detect", files={"image": ("t.png", TINY_PNG, "image/png")})
    after = client.get("/health/stats").json()
    assert after["metrics"]["detection_count"] == before + 1
    assert "Operating Scissors" in after["instrument_model"]["classes"]


# --- Ask SPAI grounding ------------------------------------------------------

def test_ask_prompt_includes_reference_for_the_held_instrument():
    prompt = build_context(
        "inspection", 1,
        "gloves detected, holding Mayo-Hegar Needle Holder (91%)",
        "what am I holding?",
    )
    assert "Instrument reference:" in prompt
    assert "Mayo-Hegar Needle Holder (Needle holder)" in prompt
    assert "Operating Scissors" not in prompt


def test_ask_prompt_has_no_reference_when_no_instrument_is_named():
    prompt = build_context("packaging", 0, "gloves detected", "which wrap do I use?")
    assert "Instrument reference:" not in prompt
