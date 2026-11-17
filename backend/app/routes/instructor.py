"""
The instructor dashboard: one page, and the API behind it.

Every API route resolves the signed-in instructor first and works only on
that instructor's organization. Routes that change who can get in, delete
records or change the procedure are admin-only, and each one is written to
the organization's activity log.
"""
from __future__ import annotations

import csv
import io
import json
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

from app import instruments, protocol, security
from app.logging_config import get_logger
from app.store import LOGIN_TTL, StoreError, get_store

router = APIRouter(prefix="/instructor")
api = APIRouter(prefix="/instructor/api")
logger = get_logger(__name__)

PAGE = Path(__file__).parent.parent / "static" / "instructor.html"

Instructor = Depends(security.current_instructor)
Admin = Depends(security.require_admin)


def _fail(e: StoreError, status: int = 400) -> HTTPException:
    return HTTPException(status_code=status, detail=str(e))


def _log(who: dict, action: str, detail: str = "") -> None:
    get_store().audit(who["org_id"], who["email"], action, detail)


def _set_login_cookie(response: Response, request: Request, instructor_id: str) -> None:
    token = get_store().create_login(instructor_id)
    response.set_cookie(security.COOKIE_NAME, token, httponly=True, samesite="strict",
                        secure=security.is_https(request), max_age=LOGIN_TTL, path="/")


# ---- page, sign-in, invites ---------------------------------------------------

@router.get("", response_class=HTMLResponse)
def dashboard() -> HTMLResponse:
    return HTMLResponse(PAGE.read_text(encoding="utf-8"), headers={
        # The dashboard never needs to be framed by another site, and loads
        # nothing but its own script and the fonts.
        "X-Frame-Options": "DENY",
        "Referrer-Policy": "no-referrer",
        "X-Content-Type-Options": "nosniff",
        "Content-Security-Policy": ("default-src 'self'; script-src 'self' 'unsafe-inline'; "
                                    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
                                    "font-src https://fonts.gstatic.com; img-src 'self' data:; "
                                    "connect-src 'self'; frame-ancestors 'none'; form-action 'self'"),
    })


@router.get("/status")
def status(request: Request) -> dict:
    who = get_store().instructor_for_login(request.cookies.get(security.COOKIE_NAME))
    if who is None:
        return {"signed_in": False}
    org = get_store().get_org(who["org_id"]) or {}
    return {"signed_in": True, "instructor": {k: who[k] for k in ("id", "name", "email", "role")},
            "organization": {"id": org.get("id"), "name": org.get("name")}}


class Login(BaseModel):
    email: str = Field(..., max_length=200)
    password: str = Field(..., max_length=200)


@router.post("/login")
def login(body: Login, request: Request, response: Response) -> dict:
    email = body.email.strip().lower()
    if not (security.login_limiter.hit("email:" + email) and security.login_limiter.hit("ip:" + security.client_address(request))):
        raise HTTPException(status_code=429, detail="Too many sign-in attempts. Wait a few minutes and try again.")
    who = get_store().authenticate(email, body.password)
    if who is None:
        logger.warning("Failed dashboard sign-in")
        raise HTTPException(status_code=401, detail="That email and password don't match an active account.")
    _set_login_cookie(response, request, who["id"])
    _log(who, "signed in")
    return {"signed_in": True}


@router.post("/logout")
def logout(request: Request, response: Response) -> dict:
    get_store().end_login(request.cookies.get(security.COOKIE_NAME))
    response.delete_cookie(security.COOKIE_NAME, path="/")
    return {"signed_in": False}


@router.get("/invite/{token}")
def peek_invite(token: str) -> dict:
    invite = get_store().peek_invite(token)
    if invite is None:
        raise HTTPException(status_code=404, detail="This invite link has expired or was already used. Ask your admin for a new one.")
    return invite


class AcceptInvite(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    password: str = Field(..., max_length=200)


@router.post("/invite/{token}")
def accept_invite(token: str, body: AcceptInvite, request: Request, response: Response) -> dict:
    if not security.login_limiter.hit("ip:" + security.client_address(request)):
        raise HTTPException(status_code=429, detail="Too many attempts. Wait a few minutes.")
    try:
        who = get_store().accept_invite(token, body.name, body.password)
    except StoreError as e:
        raise _fail(e) from e
    _set_login_cookie(response, request, who["id"])
    _log(who, "joined", f"as {who['role']}")
    return {"signed_in": True}


class PasswordChange(BaseModel):
    current: str = Field(..., max_length=200)
    new: str = Field(..., max_length=200)


@api.post("/account/password")
def change_password(body: PasswordChange, request: Request, response: Response, who: dict = Instructor) -> dict:
    try:
        get_store().set_password(who["id"], body.current, body.new)
    except StoreError as e:
        raise _fail(e) from e
    _log(who, "changed password")
    _set_login_cookie(response, request, who["id"])  # other browsers were signed out; keep this one
    return {"changed": True}


# ---- class ---------------------------------------------------------------------

@api.get("/overview")
def overview(who: dict = Instructor) -> dict:
    return get_store().overview(who["org_id"])


class NewLearners(BaseModel):
    names: list[str] = Field(..., min_length=1, max_length=200)
    cohort: str = Field(default="", max_length=60)


@api.post("/learners")
def add_learners(body: NewLearners, who: dict = Instructor) -> dict:
    """Adds learners and returns each one's PIN. This is the only time the
    PINs are shown; the dashboard offers them as a printable sheet."""
    store = get_store()
    added = [store.add_learner(who["org_id"], name, body.cohort) for name in body.names if name.strip()]
    if not added:
        raise HTTPException(status_code=400, detail="Enter at least one name.")
    _log(who, "added learners", f"{len(added)} to '{body.cohort}'")
    return {"added": added}


def _learner_or_404(who: dict, learner_id: str) -> dict:
    learner = get_store().get_learner(who["org_id"], learner_id)
    if learner is None:
        raise HTTPException(status_code=404, detail="That learner isn't on your roster.")
    return learner


@api.get("/learners/{learner_id}")
def learner_detail(learner_id: str, who: dict = Instructor) -> dict:
    learner = _learner_or_404(who, learner_id)
    return {"learner": learner, "sessions": get_store().list_sessions(who["org_id"], learner_id)}


@api.post("/learners/{learner_id}/reset-pin")
def reset_pin(learner_id: str, who: dict = Instructor) -> dict:
    learner = _learner_or_404(who, learner_id)
    pin = get_store().reset_pin(who["org_id"], learner_id)
    _log(who, "issued a new PIN", learner["name"])
    return {"learner": learner, "pin": pin}


@api.delete("/learners/{learner_id}")
def delete_learner(learner_id: str, who: dict = Admin) -> dict:
    """Erase a learner and every run recorded for them. Not reversible."""
    learner = _learner_or_404(who, learner_id)
    get_store().delete_learner(who["org_id"], learner_id)
    _log(who, "erased a learner and their runs", learner["name"])
    return {"deleted": True}


@api.get("/learners/{learner_id}/export")
def export_learner(learner_id: str, who: dict = Instructor) -> Response:
    """Everything held about one learner, as a single JSON file."""
    learner = _learner_or_404(who, learner_id)
    store = get_store()
    runs = [store.get_session(who["org_id"], s["id"]) for s in store.list_sessions(who["org_id"], learner_id)]
    _log(who, "exported a learner's record", learner["name"])
    return Response(json.dumps({"learner": learner, "sessions": runs}, indent=2), media_type="application/json",
                    headers={"Content-Disposition": f'attachment; filename="spai-learner-{learner_id}.json"'})


@api.get("/sessions/{session_id}")
def session_detail(session_id: str, who: dict = Instructor) -> dict:
    session = get_store().get_session(who["org_id"], session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="That run doesn't exist.")
    return session


@api.delete("/sessions/{session_id}")
def delete_session(session_id: str, who: dict = Admin) -> dict:
    if not get_store().delete_session(who["org_id"], session_id):
        raise HTTPException(status_code=404, detail="That run doesn't exist.")
    _log(who, "deleted a run", session_id)
    return {"deleted": True}


@api.get("/export.csv")
def export_csv(who: dict = Instructor) -> Response:
    """Every run, one row each, for a gradebook or a spreadsheet."""
    store = get_store()
    out = io.StringIO()
    writer = csv.writer(out)
    writer.writerow(["learner", "cohort", "date", "result", "score", "completed", "stations_completed",
                     "contamination_events", "duration_minutes", "identity", "instruments_recognised", "headset", "run_id"])
    cohorts = {l["id"]: l["cohort"] for l in store.list_learners(who["org_id"])}
    for s in store.list_sessions(who["org_id"], limit=100000):
        writer.writerow([
            _safe_cell(s["learner_name"]), _safe_cell(cohorts.get(s["learner_id"], "")), s["started_at"],
            s["verdict_label"], s["score"], "yes" if s["completed"] else "no", s["stations_completed"],
            s["contamination_count"], round(s["duration_s"] / 60, 1), s["identity"],
            _safe_cell("; ".join(s["instruments_seen"])), _safe_cell(s["headset"]), s["id"],
        ])
    _log(who, "exported all runs as CSV")
    return Response(out.getvalue(), media_type="text/csv",
                    headers={"Content-Disposition": 'attachment; filename="spai-runs.csv"'})


def _safe_cell(value: str) -> str:
    """Stop a name like '=HYPERLINK(...)' being run as a formula when the
    export is opened in a spreadsheet."""
    return "'" + value if value[:1] in ("=", "+", "-", "@", "\t", "\r") else value


@api.delete("/demo")
def delete_demo(who: dict = Admin) -> dict:
    """Remove the sample cohort created by `python -m app.seed_demo`."""
    removed = get_store().delete_demo_data(who["org_id"])
    _log(who, "removed sample data", f"{removed} learners")
    return {"deleted_learners": removed}


# ---- protocol ------------------------------------------------------------------

@api.get("/protocol")
def read_protocol(who: dict = Instructor) -> dict:
    """The protocol plus the full instrument list, for the editor."""
    return {**protocol.for_org(who["org_id"]),
            "catalog": [{"key": i.key, "name": i.name} for i in instruments.all_instruments()]}


@api.put("/protocol")
def save_protocol(candidate: dict, who: dict = Admin) -> dict:
    try:
        saved = protocol.save_for_org(who["org_id"], candidate, who["email"])
    except (protocol.ProtocolError, TypeError, ValueError) as e:
        raise HTTPException(status_code=422, detail=str(e)) from e
    _log(who, "edited the protocol", f"version {saved['version']}")
    return saved


@api.post("/protocol/reset")
def reset_protocol(who: dict = Admin) -> dict:
    _log(who, "reset the protocol to standard")
    return protocol.reset_for_org(who["org_id"])


# ---- headsets ------------------------------------------------------------------

@api.get("/headsets")
def headsets(who: dict = Instructor) -> dict:
    return {"headsets": get_store().list_devices(who["org_id"])}


@api.post("/headsets/pairing-code")
def pairing_code(request: Request, who: dict = Admin) -> dict:
    """A one-time code to type on a headset. Shown with this server's
    address, which the headset also needs."""
    code = get_store().create_pairing_code(who["org_id"])
    _log(who, "created a headset pairing code")
    base = str(request.base_url).rstrip("/")
    if security.is_https(request):
        base = base.replace("http://", "https://", 1)
    return {**code, "server": base}


class Rename(BaseModel):
    name: str = Field(..., min_length=1, max_length=60)


@api.patch("/headsets/{device_id}")
def rename_headset(device_id: str, body: Rename, who: dict = Admin) -> dict:
    try:
        found = get_store().rename_device(who["org_id"], device_id, body.name)
    except StoreError as e:
        raise _fail(e) from e
    if not found:
        raise HTTPException(status_code=404, detail="That headset isn't connected to your organization.")
    _log(who, "renamed a headset", body.name)
    return {"renamed": True}


@api.delete("/headsets/{device_id}")
def revoke_headset(device_id: str, who: dict = Admin) -> dict:
    """Disconnect a headset. It stops working immediately; runs it already
    sent are kept. To use it again, pair it with a new code."""
    if not get_store().revoke_device(who["org_id"], device_id):
        raise HTTPException(status_code=404, detail="That headset isn't connected to your organization.")
    _log(who, "disconnected a headset", device_id)
    return {"disconnected": True}


# ---- team ----------------------------------------------------------------------

@api.get("/team")
def team(who: dict = Instructor) -> dict:
    return {"instructors": get_store().list_instructors(who["org_id"]), "you": who["id"]}


class Invite(BaseModel):
    email: str = Field(..., max_length=200)
    role: str = Field(default="instructor", pattern="^(admin|instructor)$")


@api.post("/team/invite")
def invite(body: Invite, request: Request, who: dict = Admin) -> dict:
    """An invite link to send to a colleague. Valid for a week, works once."""
    try:
        token = get_store().create_invite(who["org_id"], body.email, body.role)
    except StoreError as e:
        raise _fail(e) from e
    _log(who, "invited an instructor", f"{body.email.strip().lower()} as {body.role}")
    base = str(request.base_url).rstrip("/")
    if security.is_https(request):
        base = base.replace("http://", "https://", 1)
    return {"link": f"{base}/instructor#invite/{token}", "expires_in_days": 7}


class TeamUpdate(BaseModel):
    role: Optional[str] = Field(default=None, pattern="^(admin|instructor)$")
    disabled: Optional[bool] = None


@api.patch("/team/{instructor_id}")
def update_member(instructor_id: str, body: TeamUpdate, who: dict = Admin) -> dict:
    if instructor_id == who["id"]:
        raise HTTPException(status_code=400, detail="You can't change your own access. Ask another admin.")
    store = get_store()
    try:
        member = store.get_instructor(who["org_id"], instructor_id)
        if member is None:
            raise HTTPException(status_code=404, detail="That instructor isn't in your organization.")
        if body.role is not None:
            member = store.set_role(who["org_id"], instructor_id, body.role)
            _log(who, "changed a role", f"{member['email']} → {body.role}")
        if body.disabled is not None:
            member = store.set_disabled(who["org_id"], instructor_id, body.disabled)
            _log(who, "removed access" if body.disabled else "restored access", member["email"])
    except StoreError as e:
        raise _fail(e) from e
    return member


@api.get("/activity")
def activity(who: dict = Admin) -> dict:
    return {"events": get_store().list_audit(who["org_id"])}
