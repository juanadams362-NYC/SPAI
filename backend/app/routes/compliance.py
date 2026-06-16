"""Compliance endpoint — exposes the FSM so the app can drive the workflow."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.compliance.engine import ComplianceEngine
from app.compliance.states import WorkflowStep, ComplianceEvent
from app.logging_config import get_logger

router = APIRouter(prefix="/compliance")
logger = get_logger(__name__)

# One engine instance for the running session. A real multi-user system
# would key these by session id; for now a single shared workflow is enough.
_engine = ComplianceEngine()


class EventRequest(BaseModel):
    """Body for posting an event to the FSM."""
    event: ComplianceEvent
    step: WorkflowStep | None = None


def _state_payload() -> dict:
    """Current machine state in a JSON-friendly shape."""
    return {
        "state": _engine.state.value,
        "current_step": _engine.current_step.value if _engine.current_step else None,
        "event_count": len(_engine.log),
    }


@router.get("/state")
def get_state() -> dict:
    """Return the current workflow state."""
    return _state_payload()


@router.post("/event")
def post_event(req: EventRequest) -> dict:
    """Send an event to the FSM and return the outcome plus new state."""
    result = _engine.process(req.event, req.step)
    logger.info("Compliance event %s -> accepted=%s", req.event.value, result.accepted)
    return {
        "accepted": result.accepted,
        "message": result.message,
        **_state_payload(),
    }


@router.post("/reset")
def reset() -> dict:
    """Start a fresh workflow."""
    global _engine
    _engine = ComplianceEngine()
    logger.info("Compliance engine reset.")
    return _state_payload()
