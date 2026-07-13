"""
Ask endpoint — the AI trainer. Takes the user's question plus what the
app knows right now (station, step, detection state), returns a short
grounded answer. All prompt building lives in ask_spai.py, all provider
stuff lives in llm_client.py, this file is just HTTP.
"""

from fastapi import APIRouter, HTTPException
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field

from app.ask_spai import ask_spai, STATION_SCRIPTS
from app.llm_client import LLMError
from app.logging_config import get_logger

router = APIRouter()
logger = get_logger(__name__)


class AskRequest(BaseModel):
    question: str = Field(..., min_length=1, max_length=500)
    station: str = Field(..., description="e.g. decontamination, tray_assembly")
    step_index: int = Field(0, ge=0, description="0-based index of current step")
    detection_summary: str = Field("", max_length=500)


@router.post("/ask")
async def ask(req: AskRequest) -> dict:
    # Bad station name is the caller's fault -> 400, not 500.
    if req.station not in STATION_SCRIPTS:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown station '{req.station}'. Known: {', '.join(STATION_SCRIPTS)}",
        )

    try:
        # requests is blocking, so run it in a worker thread same as inference.
        answer = await run_in_threadpool(
            ask_spai, req.station, req.step_index, req.detection_summary, req.question
        )
    except LLMError as e:
        logger.error("LLM call failed: %s", e)
        # 503 = service unavailable, tells the app to show a retry message
        # instead of pretending the AI answered.
        raise HTTPException(status_code=503, detail="AI assistant is unavailable right now.")

    logger.info("Ask answered: station=%s step=%d", req.station, req.step_index)
    return {
        "answer": answer,
        "station": req.station,
        "step_index": req.step_index,
    }
