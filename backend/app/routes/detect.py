"""Detect endpoint — accepts an image, returns detected objects."""
from fastapi import APIRouter, File, UploadFile, HTTPException
from app.inference.detector import detector

router = APIRouter()

# Limit file size so I don't get DoS'd by a 1 GB upload.
MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB


@router.post("/detect")
async def detect(image: UploadFile = File(...)) -> dict:
    """
    Accepts a multipart image upload, returns detected objects.

    Request: multipart/form-data with field 'image' containing a JPEG/PNG.
    Response: JSON with a list of detections (see Detector.detect).
    """
    # Validate content type — only accept actual image uploads.
    if not image.content_type or not image.content_type.startswith("image/"):
        raise HTTPException(
            status_code=400,
            detail=f"Expected an image upload, got {image.content_type}",
        )

    # Read the bytes. await is needed because UploadFile.read is async.
    image_bytes = await image.read()

    if len(image_bytes) > MAX_FILE_SIZE_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"Image too large ({len(image_bytes)} bytes, max {MAX_FILE_SIZE_BYTES})",
        )

    return detector.detect(image_bytes)
