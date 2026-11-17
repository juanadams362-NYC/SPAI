import io
import threading
import time
from pathlib import Path
from typing import Any

from app.metrics import metrics

MODEL_PATH = Path(__file__).parent.parent.parent / "model" / "best.pt"

# Fallback labels, used in stub mode and if a weights file carries no names.
CLASS_NAMES = ["glove", "hand"]

# Only report detections at or above this confidence. Filters out noise.
CONFIDENCE_THRESHOLD = 0.25

# Boxes are gathered down to this confidence *before* overlap arbitration, so a faint
# second label on the same hand can be recognised as a duplicate and removed instead of
# slipping through on its own at the reporting threshold.
CANDIDATE_CONFIDENCE = 0.15

# Two boxes describe the same physical object when they overlap this much (IoU) ...
OVERLAP_IOU = 0.5
# ... or when this share of the smaller box sits inside the larger one.
OVERLAP_CONTAINMENT = 0.6


def _area(box: list) -> float:
    return max(0, box[2] - box[0]) * max(0, box[3] - box[1])


def boxes_conflict(a: list, b: list,
                   iou_threshold: float = OVERLAP_IOU,
                   containment_threshold: float = OVERLAP_CONTAINMENT) -> bool:
    """True when two [x1, y1, x2, y2] boxes cover the same object."""
    ix = max(0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    if inter <= 0:
        return False
    area_a, area_b = _area(a), _area(b)
    union = area_a + area_b - inter
    iou = inter / union if union > 0 else 0.0
    containment = inter / max(1.0, min(area_a, area_b))
    return iou >= iou_threshold or containment >= containment_threshold


def resolve_overlaps(detections: list) -> list:
    """Give every region of the image one label: its most confident one.

    The glove/hand model regularly labels a single hand twice — "glove" and "hand" on
    the same spot, or a faint "glove" ghost over a bare hand. Per-class NMS can't see
    that. Greedy, class-agnostic suppression (highest confidence first; a tie goes to
    glove, matching the app's rule) keeps the model's best answer for each object.
    """
    def order(d: dict):
        return (-d["confidence"], 0 if "glove" in str(d["class_name"]).lower() else 1)

    kept: list = []
    for det in sorted(detections, key=order):
        if not any(boxes_conflict(det["box"], k["box"]) for k in kept):
            kept.append(det)
    return kept


class InvalidImageError(ValueError):
    """The uploaded bytes could not be decoded as an image."""


class Detector:
    """Wraps the YOLO model. Loaded once at startup, reused per request."""

    # Glove/hand needs cross-class arbitration (two labels on one hand).
    arbitrate_overlaps: bool = True

    def __init__(self) -> None:
        self.model: Any = None
        self.model_loaded: bool = False
        self.model_path: Path = MODEL_PATH
        self.confidence_threshold: float = CONFIDENCE_THRESHOLD
        self.class_names: list[str] = list(CLASS_NAMES)
        # Requests run in a thread pool, and a YOLO model instance is not safe
        # to call from two threads at once. One inference at a time per model.
        self._lock = threading.Lock()

    def load(self) -> None:
        """Load the model from disk. Called once at app startup."""
        if self.model_path.exists():
            from ultralytics import YOLO
            self.model = YOLO(str(self.model_path))
            self.model_loaded = True
            self.class_names = self._names_from_model() or self.class_names
            print(f"[detector] loaded model from {self.model_path} — classes: {self.class_names}")
            self._warm_up()
        else:
            self.model = None
            self.model_loaded = False
            print(f"[detector] no model at {self.model_path} — running in stub mode")

    def _warm_up(self) -> None:
        """Run one throwaway inference so the first real frame isn't slow.

        The first call into a freshly loaded model pays for lazy setup — over
        a second on CPU, against ~100 ms afterwards. Paying it at startup
        keeps the first live frame from the headset from timing out.
        """
        try:
            from PIL import Image
            with self._lock:
                self.model(Image.new("RGB", (64, 64)), verbose=False)
        except Exception as e:  # warm-up is best-effort; never block startup
            print(f"[detector] warm-up skipped: {e}")

    def _names_from_model(self) -> list[str]:
        """The label list baked into the weights, in class-id order.

        Reading names from the model (instead of a hard-coded list) is what
        lets one Detector class serve both the PPE model and the instrument
        model without mislabelling one with the other's classes.
        """
        names = getattr(self.model, "names", None)
        if isinstance(names, dict):
            return [str(names[i]) for i in sorted(names)]
        if isinstance(names, (list, tuple)):
            return [str(n) for n in names]
        return []

    def label(self, class_id: int) -> str:
        if 0 <= class_id < len(self.class_names):
            return self.class_names[class_id]
        return str(class_id)

    def status(self) -> dict:
        return {
            "model_loaded": self.model_loaded,
            "model_path": str(self.model_path),
            "classes": list(self.class_names),
            "mode": "real" if self.model_loaded else "stub",
            "confidence_threshold": self.confidence_threshold,
            "overlap_arbitration": self.arbitrate_overlaps,
        }

    def detect(self, image_bytes: bytes) -> dict:
        result = self._real_detect(image_bytes) if self.model_loaded else self._stub_detect(image_bytes)
        metrics.record_detection()
        return result

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

        # Anything that goes wrong while decoding is the upload's fault, not
        # the server's. Caught broadly on purpose: Pillow raises several
        # unrelated error types for corrupt files, and newer Ultralytics
        # versions hook Image.open with fallbacks that raise their own.
        try:
            image = Image.open(io.BytesIO(image_bytes))
            image = ImageOps.exif_transpose(image) or image
            image = image.convert("RGB")
        except Exception as e:
            raise InvalidImageError(f"Could not decode image: {e}") from e

        # Gather candidates a little below the reporting threshold so duplicates can be
        # arbitrated before anything is filtered out.
        candidate_conf = (min(self.confidence_threshold, CANDIDATE_CONFIDENCE)
                          if self.arbitrate_overlaps else self.confidence_threshold)

        start = time.time()
        with self._lock:
            results = self.model(image, conf=candidate_conf, verbose=False)
        elapsed_ms = int((time.time() - start) * 1000)

        detections = []
        result = results[0]
        for box in result.boxes:
            class_id = int(box.cls[0])
            confidence = float(box.conf[0])
            coords = box.xyxy[0].tolist()
            x1, y1, x2, y2 = [int(c) for c in coords]
            detections.append({
                "class_id": class_id,
                "class_name": self.label(class_id),
                "confidence": round(confidence, 3),
                "box": [x1, y1, x2, y2],
            })

        if self.arbitrate_overlaps:
            detections = resolve_overlaps(detections)
        detections = [d for d in detections if d["confidence"] >= self.confidence_threshold]

        return {
            "detections": detections,
            "inference_time_ms": elapsed_ms,
            "mode": "real",
            "image_size": [image.width, image.height],
        }


detector = Detector()
