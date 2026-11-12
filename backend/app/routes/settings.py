from __future__ import annotations
from typing import Optional
"""Settings endpoint — read and update runtime detector settings."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.inference.detector import detector
from app.inference.tray_detector import tray_detector
from app.logging_config import get_logger

router = APIRouter(prefix="/settings")
logger = get_logger(__name__)


class SettingsUpdate(BaseModel):
    """Fields that can be changed at runtime. All optional."""
    confidence_threshold: Optional[float] = Field(default=None, ge=0.0, le=1.0)
    # How sure the instrument model must be before a box is reported at all.
    instrument_confidence_threshold: Optional[float] = Field(default=None, ge=0.0, le=1.0)
    # How sure it must be before SPAI names the instrument instead of
    # saying "an instrument".
    identify_threshold: Optional[float] = Field(default=None, ge=0.0, le=1.0)


def _payload() -> dict:
    return {
        "confidence_threshold": detector.confidence_threshold,
        "instrument_confidence_threshold": tray_detector.confidence_threshold,
        "identify_threshold": tray_detector.identify_threshold,
        "model_path": str(detector.model_path),
        "mode": "real" if detector.model_loaded else "stub",
    }


@router.get("")
def get_settings() -> dict:
    """Return the current runtime settings."""
    return _payload()


@router.patch("")
def update_settings(update: SettingsUpdate) -> dict:
    """Update runtime settings. Only provided fields change."""
    if update.confidence_threshold is not None:
        old = detector.confidence_threshold
        detector.confidence_threshold = update.confidence_threshold
        logger.info(
            "Confidence threshold changed: %.2f -> %.2f",
            old, update.confidence_threshold,
        )
    if update.instrument_confidence_threshold is not None:
        tray_detector.confidence_threshold = update.instrument_confidence_threshold
        logger.info("Instrument confidence threshold -> %.2f", update.instrument_confidence_threshold)
    if update.identify_threshold is not None:
        tray_detector.identify_threshold = update.identify_threshold
        logger.info("Identify threshold -> %.2f", update.identify_threshold)
    return _payload()
