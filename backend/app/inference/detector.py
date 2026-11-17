import io
import time
from pathlib import Path
from typing import Any


MODEL_PATH = Path(__file__).parent.parent.parent / "model" / "best.pt"
CLASS_NAMES = ["glove", "hand"]

# Only report detections at or above this confidence. Filters out noise.
CONFIDENCE_THRESHOLD = 0.25

# Boxes are gathered down to this confidence *before* overlap arbitration, so a faint
# second label on the same hand can still be recognised as a duplicate and removed —
# instead of slipping through on its own at the reporting threshold.
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
    that, so downstream the app reported "PPE check failed" while the user was gloved,
    and a ghost glove could mask a real bare hand. Greedy, class-agnostic suppression
    (highest confidence first) keeps the model's best answer for each object.
    """
    kept: list = []
    for det in sorted(detections, key=lambda d: d["confidence"], reverse=True):
        if not any(boxes_conflict(det["box"], k["box"]) for k in kept):
            kept.append(det)
    return kept


class Detector:
    """Wraps the YOLO model. Loaded once at startup, reused per request."""

    # PPE needs cross-class arbitration (glove vs hand on the same hand).
    arbitrate_overlaps: bool = True
    # Use YOLO's built-in class-agnostic NMS (cheap, IoU only).
    agnostic_nms: bool = False

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
            "overlap_arbitration": self.arbitrate_overlaps,
            "agnostic_nms": self.agnostic_nms,
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

        # Gather candidates a little below the reporting threshold so duplicates can be
        # arbitrated before anything is filtered out.
        candidate_conf = (
            min(self.confidence_threshold, CANDIDATE_CONFIDENCE)
            if self.arbitrate_overlaps
            else self.confidence_threshold
        )

        start = time.time()
        results = self.model(
            image,
            conf=candidate_conf,
            agnostic_nms=self.agnostic_nms,
            verbose=False,
        )
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
                "class_name": CLASS_NAMES[class_id] if class_id < len(CLASS_NAMES) else str(class_id),
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
        }

detector = Detector()
