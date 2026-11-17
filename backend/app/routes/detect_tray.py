"""
Detect-tray endpoint — accepts an image of a surgical tray, returns the
detected instruments (by name) AND a loaded/empty verdict.

The verdict rule: one or more instruments detected -> the tray is loaded.
Zero detected -> empty. The model finds and names instruments; this route
turns that into the tray-state answer.
"""
from fastapi import APIRouter, File, UploadFile

from app import instruments
from app.inference.tray_detector import tray_detector
from app.logging_config import get_logger
from app.routes.uploads import read_image_upload, run_detector

router = APIRouter()
logger = get_logger(__name__)


@router.post("/detect-tray")
async def detect_tray(image: UploadFile = File(...)) -> dict:
    """
    Accepts a multipart image of a tray, returns instruments + tray state.

    Response adds these fields on top of the normal detection shape:
      - instrument_count: how many instruments were detected
      - tray_state: "loaded" or "empty"
      - identified: the single most prominent instrument, with what it is
        and what to check on it (null when nothing is in frame)
    """
    image_bytes = await read_image_upload(image)
    result = await run_detector(tray_detector, image_bytes)

    count = len(result["detections"])
    result["instrument_count"] = count
    result["tray_state"] = tray_detector.tray_state(count)
    result["identified"] = instruments.identify(
        result["detections"], tray_detector.identify_threshold
    )

    logger.info(
        "Tray detection: %d instruments -> %s, mode=%s, %dms",
        count,
        result["tray_state"],
        result["mode"],
        result["inference_time_ms"],
    )
    return result
