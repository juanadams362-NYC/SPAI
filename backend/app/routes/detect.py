"""Detect endpoint — accepts an image, returns detected objects."""
from fastapi import APIRouter, File, UploadFile, HTTPException
from fastapi.concurrency import run_in_threadpool
from app.inference.detector import detector
from app.logging_config import get_logger

router = APIRouter()
logger = get_logger(__name__)

# Limit file size so the server isn't taken down by a huge upload.
MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB


@router.post("/detect")
async def detect(image: UploadFile = File(...)) -> dict:
    """
    Accepts a multipart image upload, returns detected objects.

    Request: multipart/form-data with field 'image' containing a JPEG/PNG.
    Response: JSON with a list of detections (see Detector.detect).
    """
    if not image.content_type or not image.content_type.startswith("image/"):
        logger.warning("Rejected upload with content type: %s", image.content_type)
        raise HTTPException(
            status_code=400,
            detail=f"Expected an image upload, got {image.content_type}",
        )

    image_bytes = await image.read()

    if len(image_bytes) > MAX_FILE_SIZE_BYTES:
        logger.warning("Rejected oversized upload: %d bytes", len(image_bytes))
        raise HTTPException(
            status_code=413,
            detail=f"Image too large ({len(image_bytes)} bytes, max {MAX_FILE_SIZE_BYTES})",
        )

    # Run the blocking YOLO inference in a worker thread so it doesn't
    # freeze the event loop. Other requests stay responsive meanwhile.
    result = await run_in_threadpool(detector.detect, image_bytes)

    logger.info(
        "Detection complete: %d objects, mode=%s, %dms",
        len(result["detections"]),
        result["mode"],
        result["inference_time_ms"],
    )
    return result