"""
The instructor dashboard: one page, and the API behind it.

This is the half of SPAI an instructor or program director actually opens.
Students work in the headset; this is where their runs turn into a roster,
a score trend, and something to coach from.
"""
from __future__ import annotations

import csv
import io
import json
import time
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, Field

from app import instruments, security
from app.logging_config import get_logger
from app.protocol import ProtocolError, get_protocols
from app.store import get_store

router = APIRouter(prefix="/instructor")
api = APIRouter(prefix="/instructor/api", dependencies=[Depends(security.require_instructor)])
logger = get_logger(__name__)

PAGE = Path(__file__).parent.parent / "static" / "instructor.html"

# Slow down PIN guessing: after this many wrong tries, wait out the window.
MAX_ATTEMPTS, WINDOW_SECONDS = 8, 300
_failed: list[float] = []


class Login(BaseModel):
    pin: str = Field(..., max_length=100)


class NewLearners(BaseModel):
    names: list[str] = Field(..., min_length=1, max_length=200)
    cohort: str = Field(default="", max_length=60)


@router.get("", response_class=HTMLResponse)
def dashboard() -> str:
    return PAGE.read_text(encoding="utf-8")


@router.get("/status")
def status(request: Request) -> dict:
    cookie = request.cookies.get(security.COOKIE_NAME)
    return {
        "signed_in": security._is_instructor(cookie),
        "pin_required": security.instructor_pin() is not None,
        "secured": security.is_secured(),
    }


@router.post("/login")
def login(body: Login, request: Request, response: Response) -> dict:
    now = time.time()
    _failed[:] = [t for t in _failed if now - t < WINDOW_SECONDS]
    if len(_failed) >= MAX_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many wrong PINs. Wait a few minutes and try again.")
    if not security.check_pin(body.pin):
        _failed.append(now)
        logger.warning("Wrong instructor PIN (%d recent)", len(_failed))
        raise HTTPException(status_code=401, detail="That PIN isn't right.")
    response.set_cookie(
        security.COOKIE_NAME, security.instructor_token(),
        httponly=True, samesite="lax", secure=request.url.scheme == "https", max_age=12 * 3600,
    )
    return {"signed_in": True}


@router.post("/logout")
def logout(response: Response) -> dict:
    response.delete_cookie(security.COOKIE_NAME)
    return {"signed_in": False}


# ---- data --------------------------------------------------------------------

@api.get("/overview")
def overview() -> dict:
    return get_store().overview()


@api.post("/learners")
def add_learners(body: NewLearners) -> dict:
    store = get_store()
    added = [store.add_learner(name, body.cohort) for name in body.names if name.strip()]
    if not added:
        raise HTTPException(status_code=400, detail="Enter at least one name.")
    logger.info("Added %d learner(s) to cohort '%s'", len(added), body.cohort)
    return {"added": added}


@api.get("/learners/{learner_id}")
def learner_detail(learner_id: str) -> dict:
    store = get_store()
    learner = store.get_learner(learner_id)
    if learner is None:
        raise HTTPException(status_code=404, detail="That learner isn't on the roster.")
    return {"learner": learner, "sessions": store.list_sessions(learner_id)}


@api.delete("/learners/{learner_id}")
def delete_learner(learner_id: str) -> dict:
    """Erase a learner and every run recorded for them. Not reversible."""
    if not get_store().delete_learner(learner_id):
        raise HTTPException(status_code=404, detail="That learner isn't on the roster.")
    logger.info("Learner %s and all their runs erased", learner_id)
    return {"deleted": True}


@api.get("/learners/{learner_id}/export")
def export_learner(learner_id: str) -> Response:
    """Everything held about one learner, as a single JSON file."""
    store = get_store()
    learner = store.get_learner(learner_id)
    if learner is None:
        raise HTTPException(status_code=404, detail="That learner isn't on the roster.")
    runs = [store.get_session(s["id"]) for s in store.list_sessions(learner_id)]
    body = json.dumps({"learner": learner, "sessions": runs}, indent=2)
    return Response(body, media_type="application/json",
                    headers={"Content-Disposition": f'attachment; filename="spai-learner-{learner_id}.json"'})


@api.get("/sessions/{session_id}")
def session_detail(session_id: str) -> dict:
    session = get_store().get_session(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="That run doesn't exist.")
    return session


@api.delete("/sessions/{session_id}")
def delete_session(session_id: str) -> dict:
    if not get_store().delete_session(session_id):
        raise HTTPException(status_code=404, detail="That run doesn't exist.")
    return {"deleted": True}


@api.get("/export.csv")
def export_csv() -> Response:
    """Every run, one row each, for a gradebook or a spreadsheet."""
    out = io.StringIO()
    writer = csv.writer(out)
    writer.writerow(["learner", "cohort", "date", "mode", "role", "completed", "stations_completed", "score",
                     "result", "contamination_events", "duration_minutes", "instruments_recognised", "session_id"])
    store = get_store()
    cohorts = {l["id"]: l["cohort"] for l in store.list_learners()}
    for s in store.list_sessions(limit=100000):
        writer.writerow([
            _safe_cell(s["learner_name"]), _safe_cell(cohorts.get(s["learner_id"], "")), s["started_at"], s["mode"],
            _safe_cell(s["role"]), "yes" if s["completed"] else "no", s["stations_completed"], s["score"],
            s["verdict_label"], s["contamination_count"], round(s["duration_s"] / 60, 1),
            _safe_cell("; ".join(s["instruments_seen"])), s["id"],
        ])
    return Response(out.getvalue(), media_type="text/csv",
                    headers={"Content-Disposition": 'attachment; filename="spai-sessions.csv"'})


def _safe_cell(value: str) -> str:
    """Stop a name like '=HYPERLINK(...)' being run as a formula when the
    export is opened in a spreadsheet."""
    return "'" + value if value[:1] in ("=", "+", "-", "@") else value


@api.delete("/demo")
def delete_demo() -> dict:
    """Remove the sample cohort created by `python -m app.seed_demo`."""
    return {"deleted_learners": get_store().delete_demo_data()}


# ---- protocol ----------------------------------------------------------------

@api.get("/protocol")
def read_protocol() -> dict:
    """The protocol plus the full instrument list, for the editor."""
    return {**get_protocols().current(),
            "catalog": [{"key": i.key, "name": i.name} for i in instruments.all_instruments()]}


@api.put("/protocol")
def save_protocol(candidate: dict) -> JSONResponse:
    try:
        saved = get_protocols().save(candidate)
    except (ProtocolError, TypeError, ValueError) as e:
        raise HTTPException(status_code=422, detail=str(e)) from e
    logger.info("Protocol updated to version %d", saved["version"])
    return JSONResponse(saved)


@api.post("/protocol/reset")
def reset_protocol() -> dict:
    return get_protocols().reset()
