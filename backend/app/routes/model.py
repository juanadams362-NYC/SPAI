"""Model status endpoint."""
from fastapi import APIRouter
from app.inference.detector import detector

router = APIRouter(prefix="/model")


@router.get("/status")
def model_status() -> dict:
    """Returns whether the model is loaded and what classes it knows."""
    return detector.status()
