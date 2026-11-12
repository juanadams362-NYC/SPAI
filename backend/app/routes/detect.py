"""Detect endpoint — accepts an image, returns detected objects."""
from fastapi import APIRouter, File, UploadFile

from app.inference.detector import detector
from app.logging_config import get_logger
from app.routes.uploads import read_image_upload, run_detector

router = APIRouter()
logger = get_logger(__name__)


@router.post("/detect")
async def detect(image: UploadFile = File(...)) -> dict:
    """
    Accepts a multipart image upload, returns detected objects.

    Request: multipart/form-data with field 'image' containing a JPEG/PNG.
    Response: JSON with a list of detections (see Detector.detect).
    """
    image_bytes = await read_image_upload(image)
    result = await run_detector(detector, image_bytes)

    logger.info(
        "Detection complete: %d objects, mode=%s, %dms",
        len(result["detections"]),
        result["mode"],
        result["inference_time_ms"],
    )
    return result
