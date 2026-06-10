"""Batch detect endpoint — runs detection on several images in one request."""
from fastapi import APIRouter, File, UploadFile, HTTPException
from fastapi.concurrency import run_in_threadpool

from app.inference.detector import detector
from app.logging_config import get_logger

router = APIRouter()
logger = get_logger(__name__)

MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024   # 10 MB per image
MAX_BATCH_SIZE = 16                       # cap how many images per request


@router.post("/detect/batch")
async def detect_batch(images: list[UploadFile] = File(...)) -> dict:
    """
    Accepts multiple image uploads, returns detections for each.

    Request: multipart/form-data with repeated 'images' fields.
    Response: JSON with a 'results' list, one entry per input image,
    in the same order they were sent.
    """
    if len(images) > MAX_BATCH_SIZE:
        logger.warning("Rejected oversized batch: %d images", len(images))
        raise HTTPException(
            status_code=413,
            detail=f"Too many images ({len(images)}, max {MAX_BATCH_SIZE}).",
        )

    results = []
    for index, image in enumerate(images):
        # Validate each image the same way the single endpoint does.
        if not image.content_type or not image.content_type.startswith("image/"):
            results.append({
                "index": index,
                "error": f"Expected an image, got {image.content_type}",
            })
            continue

        image_bytes = await image.read()
        if len(image_bytes) > MAX_FILE_SIZE_BYTES:
            results.append({
                "index": index,
                "error": f"Image too large ({len(image_bytes)} bytes).",
            })
            continue

        # Run the blocking inference off the event loop (same as single detect).
        detection = await run_in_threadpool(detector.detect, image_bytes)
        results.append({"index": index, **detection})

    logger.info("Batch detection complete: %d images processed", len(results))
    return {"count": len(results), "results": results}
