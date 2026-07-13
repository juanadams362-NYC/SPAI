"""
Tray detector — a SECOND model instance, separate from the glove/hand
detector. This one runs the instrument-detection model. The route that
uses it counts the detections to decide whether a tray is loaded or empty.

The underlying model was trained on a 6-instrument dataset, but in practice
it labels everything as one class — and for our purposes (counting
instruments to decide loaded vs empty) the specific instrument type doesn't
matter. So we relabel every detection to a single generic "instrument" name
instead of the misleading per-instrument labels.

We reuse the existing Detector class (no duplicated inference code) but
point it at the instrument weights.
"""

from pathlib import Path
from app.inference.detector import Detector

# Instrument model weights live alongside the PPE model, in the same
# backend/model folder.
TRAY_MODEL_PATH = Path(__file__).parent.parent.parent / "model" / "instruments_best.pt"

# What we report every detection as. The model can't reliably tell the
# instruments apart, and we only need "there is an instrument here" to count
# for loaded/empty — so everything is just "instrument".
INSTRUMENT_LABEL = "instrument"


class TrayDetector(Detector):
    """Same inference machinery as Detector, pointed at the instrument model."""

    def __init__(self) -> None:
        super().__init__()
        self.model_path = TRAY_MODEL_PATH

    # Override only the labelling: report every detection as "instrument"
    # regardless of which class id the model assigned. Everything else
    # (load, detect, _real_detect, exif handling) is inherited unchanged.
    def _real_detect(self, image_bytes: bytes) -> dict:
        result = super()._real_detect(image_bytes)
        for det in result["detections"]:
            det["class_name"] = INSTRUMENT_LABEL
        return result


# Module-level singleton, loaded once at startup (mirrors the PPE detector).
tray_detector = TrayDetector()
