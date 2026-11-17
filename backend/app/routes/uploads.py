"""Shared upload handling for the image endpoints.

Every detection route accepts the same thing — one multipart image — and has
to reject the same bad inputs. Doing it in one place keeps the limits and
the error messages identical across /detect, /detect-tray, and /analyze.
"""
from fastapi import HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool

from app.inference.detector import Detector, InvalidImageError
from app.logging_config import get_logger

logger = get_logger(__name__)

# Limit file size so the server isn't taken down by a huge upload.
MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB


async def read_image_upload(image: UploadFile) -> bytes:
    """Validate an uploaded image and return its bytes.

    Raises 400 for a non-image or empty upload and 413 for an oversized one.
    """
    if not image.content_type or not image.content_type.startswith("image/"):
        logger.warning("Rejected upload with content type: %s", image.content_type)
        raise HTTPException(
            status_code=400,
            detail=f"Expected an image upload, got {image.content_type}",
        )

    image_bytes = await image.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Uploaded image is empty.")
    if len(image_bytes) > MAX_FILE_SIZE_BYTES:
        logger.warning("Rejected oversized upload: %d bytes", len(image_bytes))
        raise HTTPException(
            status_code=413,
            detail=f"Image too large ({len(image_bytes)} bytes, max {MAX_FILE_SIZE_BYTES})",
        )
    return image_bytes


async def run_detector(model: Detector, image_bytes: bytes) -> dict:
    """Run blocking YOLO inference in a worker thread so the event loop stays
    responsive, and turn an undecodable image into a 400 instead of a 500."""
    try:
        return await run_in_threadpool(model.detect, image_bytes)
    except InvalidImageError as e:
        logger.warning("Rejected undecodable image: %s", e)
        raise HTTPException(status_code=400, detail="Could not read that image.") from e
