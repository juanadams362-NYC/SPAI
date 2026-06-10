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
from app.routes import health, model, detect, compliance, batch, settings
from app.logging_config import setup_logging, get_logger

# Configure logging before anything else so startup messages are captured.
setup_logging()
logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Runs at server startup and shutdown.

    On startup: load the model once into memory. Doing this per-request
    would be 1000x slower.
    On shutdown: nothing to clean up for now.
    """
    logger.info("Starting SPAI backend — loading model...")
    detector.load()
    status = detector.status()
    logger.info(
        "Model load complete: mode=%s, path=%s",
        status["mode"],
        status["model_path"],
    )
    yield
    logger.info("Shutting down SPAI backend.")


app = FastAPI(
    title="SPAI Backend",
    description="Sterile Processing AI — detection API for the visionOS app.",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register the route modules. Each one defines a router; attach them all.
app.include_router(health.router)
app.include_router(model.router)
app.include_router(detect.router)
app.include_router(compliance.router)
app.include_router(batch.router)
app.include_router(settings.router)


@app.get("/")
def root() -> dict:
    """Friendly landing message."""
    return {
        "name": "SPAI Backend",
        "version": "0.1.0",
        "docs": "/docs",
    }