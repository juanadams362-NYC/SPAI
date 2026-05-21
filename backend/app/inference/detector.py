"""
Detector — wraps the YOLO model so the rest of the app doesn't care
how detection actually works.

Right now this is a STUB that returns fake detections. Tomorrow when v2
is trained, we'll swap the load_model() and run_inference() bodies to
use real ultralytics.YOLO calls. The rest of the app doesn't change.

This separation is intentional: routes/detect.py imports from here and
has no idea whether the model is fake or real.
"""
from pathlib import Path
from typing import Any

# Path to the trained model weights. Doesn't exist yet — gets created
# tomorrow when v2 training finishes. The stub handles the missing file
# gracefully so the API runs without crashing.
MODEL_PATH = Path(__file__).parent.parent.parent.parent / "model-training" / "runs" / "v2" / "weights" / "best.pt"

CLASS_NAMES = ["glove", "hand"]


class Detector:
    """Singleton-ish wrapper around the YOLO model.

    Loaded once at server startup (in main.py), then reused for every
    request. Loading the model takes seconds; doing it per-request
    would tank performance.
    """

    def __init__(self) -> None:
        self.model: Any = None
        self.model_loaded: bool = False
        self.model_path: Path = MODEL_PATH

    def load(self) -> None:
        """Load the model from disk. Called once at app startup."""
        if self.model_path.exists():
            # Real loading path — kicks in once v2 is trained.
            from ultralytics import YOLO
            self.model = YOLO(str(self.model_path))
            self.model_loaded = True
            print(f"[detector] loaded model from {self.model_path}")
        else:
            # Stub path — model file doesn't exist yet.
            self.model = None
            self.model_loaded = False
            print(f"[detector] no model at {self.model_path} — running in stub mode")

    def status(self) -> dict:
        """Report whether the model is ready."""
        return {
            "model_loaded": self.model_loaded,
            "model_path": str(self.model_path),
            "classes": CLASS_NAMES,
            "mode": "real" if self.model_loaded else "stub",
        }

    def detect(self, image_bytes: bytes) -> dict:
        """Run detection on raw image bytes. Returns a list of detections.

        In stub mode, returns fake detections so the frontend can develop
        against this without waiting for v2. In real mode, runs YOLO.
        """
        if not self.model_loaded:
            return self._stub_detect(image_bytes)
        return self._real_detect(image_bytes)

    def _stub_detect(self, image_bytes: bytes) -> dict:
        """Fake detections for development. Returns two boxes regardless of input."""
        return {
            "detections": [
                {
                    "class_id": 0,
                    "class_name": "glove",
                    "confidence": 0.94,
                    "box": [120, 200, 380, 450],
                },
                {
                    "class_id": 1,
                    "class_name": "hand",
                    "confidence": 0.81,
                    "box": [500, 300, 720, 480],
                },
            ],
            "inference_time_ms": 1,
            "mode": "stub",
        }

    def _real_detect(self, image_bytes: bytes) -> dict:
        """Real YOLO inference. Wired up tomorrow once v2 is trained.

        Placeholder for now — will use PIL to decode bytes, pass to YOLO,
        format results into the same shape as _stub_detect.
        """
        raise NotImplementedError("Real inference path — implemented post-v2 training")


# Module-level singleton. Imported by main.py at startup and by detect.py per-request.
detector = Detector()
