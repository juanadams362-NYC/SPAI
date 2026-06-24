"""
Detector — wraps the YOLO model so the rest of the app doesn't care
how detection actually works.

Auto-switches between stub and real mode based on whether best.pt exists.
routes/detect.py imports from here and has no idea whether the model is
fake or real — same JSON shape either way.
"""

import io
import time
from pathlib import Path
from typing import Any

# Points at the v3 fine-tuned weights (medical/nitrile glove domain).
MODEL_PATH = Path(__file__).parent.parent.parent.parent / "model-training" / "runs" / "v3" / "weights" / "best.pt"
CLASS_NAMES = ["glove", "hand"]

# Only report detections at or above this confidence. Filters out noise.
CONFIDENCE_THRESHOLD = 0.25


class Detector:
    """Wraps the YOLO model. Loaded once at startup, reused per request."""

    def __init__(self) -> None:
        self.model: Any = None
        self.model_loaded: bool = False
        self.model_path: Path = MODEL_PATH
        self.confidence_threshold: float = CONFIDENCE_THRESHOLD

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

        # 1. Decode raw bytes into a PIL image.
        #    exif_transpose() applies any EXIF orientation flag so the image is
        #    upright — this is what Ultralytics does automatically when it loads
        #    from a file path, but PIL does NOT do it on Image.open(). Without
        #    this, phone/web images with orientation metadata get fed to the
        #    model rotated, and detection fails on otherwise-clear images.
        #    convert("RGB") drops any alpha channel.
        image = Image.open(io.BytesIO(image_bytes))
        image = ImageOps.exif_transpose(image) or image
        image = image.convert("RGB")

        # 2. Run inference. verbose=False keeps the console quiet.
        start = time.time()
        results = self.model(image, conf=self.confidence_threshold, verbose=False)
        elapsed_ms = int((time.time() - start) * 1000)

        # 3. Parse results. YOLO returns a list (one entry per image);
        #    we sent one image, so take results[0].
        detections = []
        result = results[0]
        for box in result.boxes:
            class_id = int(box.cls[0])
            confidence = float(box.conf[0])
            # xyxy = [x1, y1, x2, y2] in pixel coordinates.
            coords = box.xyxy[0].tolist()
            x1, y1, x2, y2 = [int(c) for c in coords]
            detections.append({
                "class_id": class_id,
                "class_name": CLASS_NAMES[class_id] if class_id < len(CLASS_NAMES) else str(class_id),
                "confidence": round(confidence, 3),
                "box": [x1, y1, x2, y2],
            })

        # 4. Same shape as _stub_detect — only mode and contents differ.
        return {
            "detections": detections,
            "inference_time_ms": elapsed_ms,
            "mode": "real",
        }


# Module-level singleton. Imported by main.py at startup and by detect.py per-request.
detector = Detector()