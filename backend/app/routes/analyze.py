"""
Analyze endpoint — everything the headset needs to know about one frame,
from one upload.

The app used to send every camera frame twice: once to /detect for gloves
and hands, once to /detect-tray for instruments. /analyze takes the frame
once, runs both models side by side, and answers three questions together:

  1. PPE        — are there gloves? is a bare hand visible?
  2. Tray       — how many instruments, and is the tray loaded?
  3. Identify   — which instrument is the user holding up, and what is it?

Half the upload traffic, one round trip, and the "held" judgement can use
both models' boxes — an instrument with a hand on it is the one being shown.
"""
import asyncio

from fastapi import APIRouter, File, UploadFile

from app import instruments
from app.inference.detector import detector
from app.inference.tray_detector import tray_detector
from app.logging_config import get_logger
from app.routes.uploads import read_image_upload, run_detector

router = APIRouter()
logger = get_logger(__name__)


@router.post("/analyze")
async def analyze(image: UploadFile = File(...)) -> dict:
    """
    Accepts a multipart image, returns PPE detections, named instruments,
    tray state, and the identified instrument.

    Response:
      - detections:        glove / hand boxes (same shape as /detect)
      - instruments:       instrument boxes, each with class_name, key,
                           category and a `held` flag
      - instrument_count:  number of instruments in frame
      - tray_state:        "loaded" or "empty"
      - identified:        the instrument being shown, or null
      - inference_time_ms: wall time for both models
      - mode:              "real" if both models ran, "stub" if either is stubbed
    """
    image_bytes = await read_image_upload(image)

    ppe, tray = await asyncio.gather(
        run_detector(detector, image_bytes),
        run_detector(tray_detector, image_bytes),
    )

    found = tray["detections"]
    instruments.mark_held(found, ppe["detections"])
    identified = instruments.identify(found, tray_detector.identify_threshold)
    count = len(found)

    logger.info(
        "Analyze: %d ppe, %d instruments, identified=%s, %d+%dms",
        len(ppe["detections"]),
        count,
        identified["key"] if identified else None,
        ppe["inference_time_ms"],
        tray["inference_time_ms"],
    )

    result = {
        "detections": ppe["detections"],
        "instruments": found,
        "instrument_count": count,
        "tray_state": tray_detector.tray_state(count),
        "identified": identified,
        # The models run concurrently, so wall time is the slower of the two.
        "inference_time_ms": max(ppe["inference_time_ms"], tray["inference_time_ms"]),
        "mode": "real" if ppe["mode"] == "real" and tray["mode"] == "real" else "stub",
    }
    if "image_size" in ppe:
        result["image_size"] = ppe["image_size"]
    return result
