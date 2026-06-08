"""Health endpoint. Returns 'ok' if the server is alive."""
from fastapi import APIRouter

router = APIRouter()


@router.get("/health")
def health() -> dict:
    """Used by the visionOS app to verify the backend is reachable."""
    return {"status": "ok"}
