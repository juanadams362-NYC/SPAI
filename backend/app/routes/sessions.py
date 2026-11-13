"""
What the headset talks to between detections: who can sign in, what the
protocol is, and where a finished run goes.
"""
from __future__ import annotations

import os
from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app import security
from app.logging_config import get_logger
from app.protocol import get_protocols
from app.store import get_store

router = APIRouter()
# Readable without a key: an IT or privacy office should be able to check
# what the server keeps before anyone is given access.
public = APIRouter()
logger = get_logger(__name__)


class EventIn(BaseModel):
    at: str = Field(..., max_length=40)
    kind: str = Field(..., max_length=40)
    station: Optional[str] = Field(default=None, max_length=40)
    message: str = Field(default="", max_length=300)


class SessionIn(BaseModel):
    """One run, uploaded whole when it ends. Built on the headset so a run
    survives the network dropping mid-session."""
    learner_id: Optional[str] = Field(default=None, max_length=40)
    learner_name: str = Field(default="Guest", max_length=80)
    role: str = Field(default="Trainee", max_length=30)
    mode: str = Field(default="assessed", pattern="^(assessed|practice)$")
    headset: str = Field(default="", max_length=60)
    started_at: str = Field(..., max_length=40)
    ended_at: str = Field(..., max_length=40)
    duration_s: int = Field(default=0, ge=0, le=24 * 3600)
    completed: bool = False
    stations_completed: int = Field(default=0, ge=0, le=5)
    events: list[EventIn] = Field(default_factory=list, max_length=2000)
    instruments_seen: list[str] = Field(default_factory=list, max_length=50)
    app_version: str = Field(default="", max_length=30)
    detection_mode: str = Field(default="", max_length=30)


@router.get("/learners")
def learners() -> dict:
    """The roster, for the sign-in list on the headset."""
    return {"learners": [{"id": l["id"], "name": l["name"], "cohort": l["cohort"]}
                         for l in get_store().list_learners()]}


@router.get("/protocol")
def protocol() -> dict:
    """The institution's station scripts, count sheets, and scoring rubric."""
    return get_protocols().current()


@router.put("/sessions/{session_id}")
def upload_session(session_id: str, body: SessionIn) -> dict:
    """Store a finished (or abandoned) run and return it scored.

    Idempotent: a headset that retries after a dropped connection replaces
    its earlier upload rather than adding a second copy.
    """
    if not 8 <= len(session_id) <= 64 or not session_id.replace("-", "").isalnum():
        raise HTTPException(status_code=400, detail="Session id must be 8-64 letters, digits or dashes.")
    record = {"id": session_id, **body.model_dump()}
    saved = get_store().save_session(record, get_protocols().current()["rubric"])
    logger.info("Session %s stored: %s, score %d, %s", session_id, saved["learner_name"], saved["score"], saved["verdict"])
    return saved


@public.get("/privacy")
def privacy() -> dict:
    """What this server keeps, in plain terms. Linked from the dashboard so
    an institution's IT or privacy office can read it without asking."""
    retention = os.getenv("SPAI_RETENTION_DAYS")
    return {
        "camera_frames": "Never stored. Images sent for detection are processed in memory and discarded.",
        "stored": [
            "Learner names and cohort labels entered by an instructor",
            "For each run: start and end time, the steps and alerts that occurred, instruments recognised, and the score",
        ],
        "not_collected": ["Video or photos", "Audio", "Faces or other biometric identifiers", "Patient information"],
        "retention": f"Runs are deleted {retention} days after they end." if retention
                     else "Runs are kept until an instructor deletes them.",
        "erasure": "Deleting a learner in the dashboard permanently removes that learner and all of their runs.",
        "export": "An instructor can download every run as CSV, or one learner's full record as JSON.",
        "secured": security.is_secured(),
    }
