from __future__ import annotations
from typing import Optional
"""Compliance endpoint — exposes the FSM so the app can drive the workflow."""
import threading
from collections import OrderedDict

from fastapi import APIRouter, Header
from pydantic import BaseModel

from app.compliance.engine import ComplianceEngine
from app.compliance.states import WorkflowStep, ComplianceEvent
from app.logging_config import get_logger

router = APIRouter(prefix="/compliance")
logger = get_logger(__name__)

# One engine per headset session. The app sends its session id in the
# X-SPAI-Session header; each id gets its own workflow state.
#
# This used to be a single engine shared by every caller, which is fine for
# one headset on a desk and wrong for a classroom: two students working at
# once would advance, halt, and reset each other's workflow.
DEFAULT_SESSION = "default"
MAX_ENGINES = 500

_engines: "OrderedDict[str, ComplianceEngine]" = OrderedDict()
_engines_lock = threading.Lock()


def _engine_for(session: str | None, fresh: bool = False) -> ComplianceEngine:
    key = (session or DEFAULT_SESSION)[:64]
    with _engines_lock:
        if fresh or key not in _engines:
            _engines[key] = ComplianceEngine()
        _engines.move_to_end(key)
        # Headsets come and go; forget the least recently used workflows
        # rather than grow without bound.
        while len(_engines) > MAX_ENGINES:
            _engines.popitem(last=False)
        return _engines[key]


class EventRequest(BaseModel):
    """Body for posting an event to the FSM."""
    event: ComplianceEvent
    step: Optional[WorkflowStep] = None


def _state_payload(engine: ComplianceEngine) -> dict:
    """Current machine state in a JSON-friendly shape."""
    return {
        "state": engine.state.value,
        "current_step": engine.current_step.value if engine.current_step else None,
        "event_count": len(engine.log),
    }


@router.get("/state")
def get_state(x_spai_session: Optional[str] = Header(default=None)) -> dict:
    """Return this session's workflow state."""
    return _state_payload(_engine_for(x_spai_session))


@router.post("/event")
def post_event(req: EventRequest, x_spai_session: Optional[str] = Header(default=None)) -> dict:
    """Send an event to this session's FSM and return the outcome plus new state."""
    engine = _engine_for(x_spai_session)
    result = engine.process(req.event, req.step)
    logger.info("Compliance event %s -> accepted=%s", req.event.value, result.accepted)
    return {
        "accepted": result.accepted,
        "message": result.message,
        **_state_payload(engine),
    }


@router.post("/reset")
def reset(x_spai_session: Optional[str] = Header(default=None)) -> dict:
    """Start a fresh workflow for this session only."""
    engine = _engine_for(x_spai_session, fresh=True)
    logger.info("Compliance engine reset.")
    return _state_payload(engine)
