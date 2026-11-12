"""
Tray / instrument detector — a SECOND model instance, separate from the
glove/hand detector. This one runs the instrument-detection model.

The model is trained on six named instruments (Adson dressing forceps,
Babcock tissue forceps, Halsted mosquito forceps, Mayo-Hegar needle holder,
operating scissors, No. 3 scalpel handle).

Earlier versions of this file threw the names away and reported every hit as
a generic "instrument". Two things were wrong, and both are fixed:

  1. The shared Detector named this model's classes with the PPE model's
     ["glove", "hand"] list. It now reads the label list from each weights
     file.
  2. The v4 weights themselves called every instrument by one name. The v5
     weights (see model-training/v5_instruments.md) tell them apart.

So the real instrument names come through and we keep them:

  - class_name : the instrument's display name ("Mayo-Hegar Needle Holder")
  - key        : stable id for lookups ("mayo_hegar_needle_holder")
  - category   : always "instrument", so callers that only want to count
                 instruments (tray loaded / empty) don't need to know names

We reuse the existing Detector class (no duplicated inference code) but
point it at the instrument weights.
"""
from pathlib import Path

from app import instruments
from app.inference.detector import Detector

# Instrument model weights live alongside the PPE model, in the same
# backend/model folder.
TRAY_MODEL_PATH = Path(__file__).parent.parent.parent / "model" / "instruments_best.pt"

# Category tag on every detection from this model.
INSTRUMENT_LABEL = instruments.GENERIC_LABEL

# One or more instruments on the tray = loaded. Zero = empty.
LOADED_MIN_INSTRUMENTS = 1


class TrayDetector(Detector):
    """Same inference machinery as Detector, pointed at the instrument model."""

    def __init__(self) -> None:
        super().__init__()
        self.model_path = TRAY_MODEL_PATH
        self.class_names = [info.name for info in instruments.all_instruments()]
        # Below this we report "an instrument" rather than guess its name.
        self.identify_threshold: float = instruments.DEFAULT_IDENTIFY_THRESHOLD

    def status(self) -> dict:
        status = super().status()
        status["identify_threshold"] = self.identify_threshold
        return status

    def detect(self, image_bytes: bytes) -> dict:
        result = super().detect(image_bytes)
        for det in result["detections"]:
            raw = det["class_name"]
            det["category"] = INSTRUMENT_LABEL
            det["key"] = instruments.key_for(raw)
            det["class_name"] = instruments.display_name(raw)
        return result

    def _stub_detect(self, image_bytes: bytes) -> dict:
        """Fake instrument hit for development, so the app can exercise the
        identification flow before the weights are in place."""
        return {
            "detections": [
                {
                    "class_id": 3,
                    "class_name": "Mayo Hegar Needle Holder",
                    "confidence": 0.9,
                    "box": [140, 220, 360, 430],
                },
            ],
            "inference_time_ms": 1,
            "mode": "stub",
        }

    @staticmethod
    def tray_state(count: int) -> str:
        return "loaded" if count >= LOADED_MIN_INSTRUMENTS else "empty"


# Module-level singleton, loaded once at startup (mirrors the PPE detector).
tray_detector = TrayDetector()
