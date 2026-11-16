"""
SPAI backend entry point.

Run locally with:
    cd backend
    uvicorn app.main:app --reload --port 8000
"""
from contextlib import asynccontextmanager
from fastapi import FastAPI

from app.inference.detector import detector
from app.inference.tray_detector import tray_detector
import os

from fastapi import Depends

from app import security
from app.routes import (
    health, model, detect, compliance, batch, settings, detect_tray, ask,
    analyze, instruments, sessions, instructor,
)
from app.store import get_store
from app.logging_config import setup_logging, get_logger
from app.metrics import metrics

# Configure logging before anything else so startup messages are captured.
setup_logging()
logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Runs at server startup and shutdown.

    On startup: load the models once into memory. Doing this per-request
    would be 1000x slower.
    On shutdown: nothing to clean up for now.
    """
    logger.info("Starting SPAI backend — loading models...")

    # PPE model (glove/hand).
    detector.load()
    status = detector.status()
    logger.info(
        "PPE model load complete: mode=%s, path=%s",
        status["mode"],
        status["model_path"],
    )

    # Tray/instrument model — separate model for tray-state detection.
    tray_detector.load()
    tray_status = tray_detector.status()
    logger.info(
        "Tray model load complete: mode=%s, path=%s",
        tray_status["mode"],
        tray_status["model_path"],
    )

    # Records: open the database, apply the retention policy if one is set.
    store = get_store()
    retention = os.getenv("SPAI_RETENTION_DAYS")
    if retention and retention.isdigit():
        purged = store.purge_older_than(int(retention))
        logger.info("Retention: removed %d run(s) older than %s days", purged, retention)
    if not store.list_orgs():
        logger.warning("No organizations yet. Create one with: python -m app.admin create-org --help")
    if not os.getenv("SPAI_OPERATOR_KEY"):
        logger.info("SPAI_OPERATOR_KEY is not set; server-wide detection settings are locked.")

    yield
    logger.info("Shutting down SPAI backend.")


app = FastAPI(
    title="SPAI Backend",
    description="Sterile Processing AI — detection API for the visionOS app.",
    version="0.4.0",
    lifespan=lifespan,
)

# No CORS: the headsets are a native app and the dashboard is served from
# this same origin, so no other website ever needs to call this server.


@app.middleware("http")
async def no_store(request, call_next):
    """Nothing this server returns should be cached by a shared proxy or a
    browser's back button: it is all student records or live state."""
    response = await call_next(request)
    response.headers.setdefault("Cache-Control", "no-store")
    return response

@app.middleware("http")
async def count_requests(request, call_next):
    """Count every request and any 5xx error for the health dashboard."""
    metrics.record_request()
    response = await call_next(request)
    if response.status_code >= 500:
        metrics.record_error()
    return response


# Register the route modules.
#
# Open to anyone: liveness, the privacy statement, headset pairing (which
# needs a one-time code) and the dashboard page itself (which asks for a
# sign-in). Everything that reads or writes a school's data checks either a
# headset token or an instructor sign-in, inside the route.
headset = [Depends(security.current_device)]
app.include_router(health.router)
app.include_router(sessions.public)                           # /privacy, /device/pair
app.include_router(instructor.router)                         # dashboard page, sign-in, invites
app.include_router(instructor.api)                            # dashboard data
app.include_router(sessions.router)                           # roster, PIN check, protocol, run upload
app.include_router(compliance.router)                         # per-headset workflow state
app.include_router(ask.router)                                # AI trainer chat
app.include_router(model.router, dependencies=headset)
app.include_router(detect.router, dependencies=headset)
app.include_router(detect_tray.router, dependencies=headset)
app.include_router(analyze.router, dependencies=headset)
app.include_router(instruments.router, dependencies=headset)
app.include_router(batch.router, dependencies=headset)
app.include_router(settings.router, dependencies=headset)


@app.get("/")
def root() -> dict:
    """Friendly landing message."""
    return {
        "name": "SPAI Backend",
        "version": "0.4.0",
        "docs": "/docs",
        "instructor": "/instructor",
    }
