"""
SPAI backend entry point.

Run locally with:
    cd backend
    uvicorn app.main:app --reload --port 8000
"""
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

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
    secured = security.is_secured()
    if not all(secured.values()):
        logger.warning(
            "Running without %s. Fine on a desk; set SPAI_API_KEY and SPAI_INSTRUCTOR_PIN before putting this online.",
            " or ".join(name for name, ok in (("a headset key", secured["headset_key"]),
                                               ("an instructor PIN", secured["instructor_pin"])) if not ok),
        )

    yield
    logger.info("Shutting down SPAI backend.")


app = FastAPI(
    title="SPAI Backend",
    description="Sterile Processing AI — detection API for the visionOS app.",
    version="0.3.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    # The headset is a native app and the dashboard is served from this same
    # origin, so nothing legitimate needs cross-site cookies.
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.middleware("http")
async def count_requests(request, call_next):
    """Count every request and any 5xx error for the health dashboard."""
    metrics.record_request()
    response = await call_next(request)
    if response.status_code >= 500:
        metrics.record_error()
    return response


# Register the route modules. Each one defines a router; attach them all.
#
# Open to anyone: liveness and the dashboard page itself (which asks for the
# PIN). Everything a headset calls needs the site's key when one is set.
headset = [Depends(security.require_headset)]
app.include_router(health.router)
app.include_router(sessions.public)                           # /privacy
app.include_router(instructor.router)                         # dashboard page + sign-in
app.include_router(instructor.api)                            # dashboard data (instructor PIN)
app.include_router(model.router, dependencies=headset)
app.include_router(detect.router, dependencies=headset)
app.include_router(detect_tray.router, dependencies=headset)  # tray-state detection
app.include_router(analyze.router, dependencies=headset)      # PPE + instruments + identification
app.include_router(instruments.router, dependencies=headset)  # instrument reference cards
app.include_router(compliance.router, dependencies=headset)
app.include_router(batch.router, dependencies=headset)
app.include_router(settings.router, dependencies=headset)
app.include_router(ask.router, dependencies=headset)          # AI trainer chat
app.include_router(sessions.router, dependencies=headset)     # roster, protocol, run upload


@app.get("/")
def root() -> dict:
    """Friendly landing message."""
    return {
        "name": "SPAI Backend",
        "version": "0.3.0",
        "docs": "/docs",
        "instructor": "/instructor",
    }
