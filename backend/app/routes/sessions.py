"""
What a paired headset talks to between detections: pairing, who may sign
in, the school's protocol, and where a finished run goes.

Every route here except pairing and /privacy needs the headset's token, and
everything it returns or accepts is limited to that headset's school.
"""
from __future__ import annotations

import os
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from app import protocol, security
from app.logging_config import get_logger
from app.store import StoreError, get_store

router = APIRouter()
# No headset token needed: a headset has none until it pairs, and an IT or
# privacy office should be able to read what the server keeps.
public = APIRouter()
logger = get_logger(__name__)

Device = Depends(security.current_device)


# ---- Pairing -----------------------------------------------------------------

class PairRequest(BaseModel):
    code: str = Field(..., min_length=4, max_length=20)
    name: str = Field(default="Headset", max_length=60)


@public.post("/device/pair")
def pair(body: PairRequest, request: Request) -> dict:
    """Trade a one-time code from the dashboard for this headset's token.

    The token is returned once. The headset keeps it in the Keychain; the
    server keeps only its hash.
    """
    if not security.pairing_limiter.hit(security.client_address(request)):
        raise HTTPException(status_code=429, detail="Too many tries. Wait a few minutes, then enter the code again.")
    try:
        device, token = get_store().redeem_pairing_code(body.code, body.name)
    except StoreError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    org = get_store().get_org(device["org_id"]) or {}
    get_store().audit(device["org_id"], f"headset:{device['name']}", "headset paired", device["name"])
    logger.info("Headset paired to org %s", device["org_id"])
    return {"token": token, "device": {"id": device["id"], "name": device["name"]},
            "organization": {"id": org.get("id"), "name": org.get("name")}}


@router.get("/device/me")
def whoami(device: dict = Device) -> dict:
    org = get_store().get_org(device["org_id"]) or {}
    return {"device": {"id": device["id"], "name": device["name"]},
            "organization": {"id": org.get("id"), "name": org.get("name")}}


@router.delete("/device/me")
def unpair(device: dict = Device) -> dict:
    """The headset disconnecting itself (Settings → Disconnect)."""
    get_store().revoke_device(device["org_id"], device["id"])
    get_store().audit(device["org_id"], f"headset:{device['name']}", "headset disconnected itself", device["name"])
    return {"disconnected": True}


# ---- Who can sign in ---------------------------------------------------------

@router.get("/learners")
def learners(device: dict = Device) -> dict:
    """This school's roster, for the sign-in list. Names and cohorts only."""
    return {"learners": [{"id": l["id"], "name": l["name"], "cohort": l["cohort"]}
                         for l in get_store().list_learners(device["org_id"])]}


class PinCheck(BaseModel):
    pin: str = Field(..., pattern=r"^\d{4}$")


@router.post("/learners/{learner_id}/verify-pin")
def verify_pin(learner_id: str, body: PinCheck, device: dict = Device) -> dict:
    """Confirm the person at the headset is who they picked."""
    if not security.pin_limiter.hit(device["id"]):
        raise HTTPException(status_code=429, detail="Too many PIN attempts from this headset. Wait a few minutes.")
    result = get_store().verify_pin(device["org_id"], learner_id, body.pin)
    if result.get("reason") == "unknown":
        raise HTTPException(status_code=404, detail="That name is no longer on your class roster.")
    return result


@router.get("/protocol")
def get_protocol(device: dict = Device) -> dict:
    """This school's station scripts, count sheets, and scoring rubric."""
    return protocol.for_org(device["org_id"])


# ---- Runs --------------------------------------------------------------------

class EventIn(BaseModel):
    at: str = Field(..., max_length=40)
    kind: str = Field(..., max_length=40)
    station: Optional[str] = Field(default=None, max_length=40)
    message: str = Field(default="", max_length=300)


class SessionIn(BaseModel):
    """One assessed run, uploaded whole when it ends. Built on the headset so
    a run survives the network dropping mid-session.

    `pin` is sent only when the learner signed in while the headset was
    offline and their PIN couldn't be checked at the time. The server checks
    it now; if it is wrong the run is kept but marked unconfirmed, so it can't
    count toward anyone's competency.
    """
    learner_id: str = Field(..., min_length=1, max_length=40)
    pin: Optional[str] = Field(default=None, pattern=r"^\d{4}$")
    role: str = Field(default="Trainee", max_length=30)
    mode: str = Field(default="assessed", pattern="^assessed$")
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


@router.put("/sessions/{session_id}")
def upload_session(session_id: str, body: SessionIn, device: dict = Device) -> dict:
    """Store a finished (or abandoned) run and return it scored.

    Idempotent: a headset that retries after a dropped connection replaces
    its earlier upload rather than adding a second copy.
    """
    if not 8 <= len(session_id) <= 64 or not session_id.replace("-", "").isalnum():
        raise HTTPException(status_code=400, detail="Run id must be 8-64 letters, digits or dashes.")
    store = get_store()
    org_id = device["org_id"]

    identity = "verified"
    if body.pin is not None:
        check = store.verify_pin(org_id, body.learner_id, body.pin)
        if check.get("reason") == "unknown":
            raise HTTPException(status_code=404, detail="That learner is no longer on this school's roster.")
        identity = "verified" if check["ok"] else "unconfirmed"

    record = {"id": session_id, **body.model_dump(exclude={"pin"})}
    try:
        saved = store.save_session(org_id, device["id"], record, protocol.for_org(org_id)["rubric"], identity)
    except StoreError as e:
        # The learner was removed from the roster after the run. Tell the
        # headset to stop retrying.
        raise HTTPException(status_code=404, detail=str(e)) from e
    logger.info("Run stored for org %s: score %d, %s, identity %s", org_id, saved["score"], saved["verdict"], identity)
    return saved


# ---- Privacy -----------------------------------------------------------------

@public.get("/privacy")
def privacy() -> dict:
    """What this server keeps, in plain terms."""
    retention = os.getenv("SPAI_RETENTION_DAYS")
    return {
        "camera_frames": ("Never stored. By default, frames stay on the headset. If a school turns that off, "
                          "frames sent for checking are processed in memory and discarded."),
        "stored": [
            "Instructor names, work emails and hashed passwords",
            "Learner names and cohort labels entered by an instructor, and a hashed 4-digit PIN for each",
            "For each assessed run: start and end time, the steps and alerts that occurred, instruments recognised, "
            "and the score. Practice runs never leave the headset.",
            "A log of instructor actions such as adding learners, deleting records and editing the protocol",
        ],
        "not_collected": ["Video or photos", "Audio", "Faces or other biometric identifiers", "Patient information"],
        "third_parties": ("Ask SPAI sends the student's question, the current station's steps and a short text "
                          "summary of what the camera sees to Google Gemini to write an answer. No images, names or "
                          "PINs are sent."),
        "separation": "Each school's records are kept separate. Instructors and headsets only ever see their own school's data.",
        "retention": f"Runs are deleted {retention} days after they end." if retention
                     else "Runs are kept until an instructor deletes them.",
        "erasure": "Deleting a learner in the dashboard permanently removes that learner and all of their runs.",
        "export": "An instructor can download every run as CSV, or one learner's full record as JSON.",
    }
