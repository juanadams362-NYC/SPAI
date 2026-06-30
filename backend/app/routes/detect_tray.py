"""
Detect-tray endpoint — accepts an image of a surgical tray, returns the
detected instruments AND a loaded/empty verdict.

The verdict rule: one or more instruments detected -> the tray is loaded.
Zero detected -> empty. The model just finds instruments; this route turns
that count into the tray-state answer.
"""

from fastapi import APIRouter, File, UploadFile, HTTPException
from fastapi.concurrency import run_in_threadpool
from app.inference.tray_detector import tray_detector
from app.logging_config import get_logger

router = APIRouter()
logger = get_logger(__name__)

MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB

# One or more instruments on the tray = loaded. Zero = empty.
LOADED_MIN_INSTRUMENTS = 1


@router.post("/detect-tray")
async def detect_tray(image: UploadFile = File(...)) -> dict:
    """
    Accepts a multipart image of a tray, returns instruments + tray state.

    Response adds two fields on top of the normal detection shape:
      - instrument_count: how many instruments were detected
      - tray_state: "loaded" or "empty"
    """
    if not image.content_type or not image.content_type.startswith("image/"):
        logger.warning("Rejected tray upload with content type: %s", image.content_type)
        raise HTTPException(
            status_code=400,
            detail=f"Expected an image upload, got {image.content_type}",
        )

    image_bytes = await image.read()

    if len(image_bytes) > MAX_FILE_SIZE_BYTES:
        logger.warning("Rejected oversized tray upload: %d bytes", len(image_bytes))
        raise HTTPException(
            status_code=413,
            detail=f"Image too large ({len(image_bytes)} bytes, max {MAX_FILE_SIZE_BYTES})",
        )

    # Run the instrument model in a worker thread (same as /detect).
    result = await run_in_threadpool(tray_detector.detect, image_bytes)

    # Count detections and derive the tray state.
    count = len(result["detections"])
    tray_state = "loaded" if count >= LOADED_MIN_INSTRUMENTS else "empty"

    result["instrument_count"] = count
    result["tray_state"] = tray_state

    logger.info(
        "Tray detection: %d instruments -> %s, mode=%s, %dms",
        count,
        tray_state,
        result["mode"],
        result["inference_time_ms"],
    )
    return result
