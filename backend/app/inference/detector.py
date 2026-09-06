

import io
import time
from pathlib import Path
from typing import Any


MODEL_PATH = Path(__file__).parent.parent.parent / "model" / "best.pt"
CLASS_NAMES = ["glove", "hand"]

# Only report detections at or above this confidence. Filters out noise.
CONFIDENCE_THRESHOLD = 0.25

# Largest share of the frame a single detection may cover before we stop believing it.
#
# A YOLO model has no "none of the above" class: point the instrument detector at a chair and
# it will force the chair into one of its six trained classes and report a box. What gives that
# away is size — instruments are photographed lying in a tray and occupy a modest slice of the
# frame, while furniture, benches and people fill it. Mirrors DetectionTuning.swift on the
# client so both paths accept the same things.
MAX_AREA_FRACTION = 0.35

# Floor for the smallest believable box, to drop specks.
MIN_AREA_FRACTION = 0.0005


class Detector:
    """Wraps the YOLO model. Loaded once at startup, reused per request."""

    def __init__(self) -> None:
        self.model: Any = None
        self.model_loaded: bool = False
        self.model_path: Path = MODEL_PATH
        self.confidence_threshold: float = CONFIDENCE_THRESHOLD
        # Gloves and hands can legitimately fill a close-up frame, so the PPE detector is far
        # more permissive about size than the instrument detector that subclasses this.
        self.max_area_fraction: float = 0.90

    def load(self) -> None:
        """Load the model from disk. Called once at app startup."""
        if self.model_path.exists():
            from ultralytics import YOLO
            self.model = YOLO(str(self.model_path))
            self.model_loaded = True
            print(f"[detector] loaded model from {self.model_path}")
        else:
            self.model = None
            self.model_loaded = False
            print(f"[detector] no model at {self.model_path} — running in stub mode")

    def status(self) -> dict:
        return {
            "model_loaded": self.model_loaded,
            "model_path": str(self.model_path),
            "classes": CLASS_NAMES,
            "mode": "real" if self.model_loaded else "stub",
            "confidence_threshold": self.confidence_threshold,
        }

    def detect(self, image_bytes: bytes) -> dict:
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
        """Real YOLO inference on the uploaded image bytes."""
        from PIL import Image, ImageOps


        image = Image.open(io.BytesIO(image_bytes))
        image = ImageOps.exif_transpose(image) or image
        image = image.convert("RGB")


        start = time.time()
        results = self.model(image, conf=self.confidence_threshold, verbose=False)
        elapsed_ms = int((time.time() - start) * 1000)


        frame_w, frame_h = image.size
        frame_area = float(frame_w * frame_h) or 1.0

        detections = []
        rejected = 0
        result = results[0]
        for box in result.boxes:
            class_id = int(box.cls[0])
            confidence = float(box.conf[0])

            coords = box.xyxy[0].tolist()
            x1, y1, x2, y2 = [int(c) for c in coords]

            if not self._is_plausible(x1, y1, x2, y2, frame_area):
                rejected += 1
                continue

            detections.append({
                "class_id": class_id,
                "class_name": CLASS_NAMES[class_id] if class_id < len(CLASS_NAMES) else str(class_id),
                "confidence": round(confidence, 3),
                "box": [x1, y1, x2, y2],
            })

        if rejected:
            print(f"[detector] rejected {rejected} implausibly sized detection(s)")

        return {
            "detections": detections,
            "inference_time_ms": elapsed_ms,
            "mode": "real",
        }

    def _is_plausible(self, x1: int, y1: int, x2: int, y2: int, frame_area: float) -> bool:
        """Reject boxes that are the wrong size to be what the model says they are."""
        w = abs(x2 - x1)
        h = abs(y2 - y1)
        if w <= 0 or h <= 0:
            return False
        fraction = (w * h) / frame_area
        return MIN_AREA_FRACTION <= fraction <= self.max_area_fraction

detector = Detector()