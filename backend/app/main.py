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
from app.routes import health, model, detect


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Runs at server startup and shutdown.

    On startup: load the model once into memory. Doing this per-request
    would be 1000x slower.
    On shutdown: nothing to clean up for now.
    """
    detector.load()
    yield


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

# Register the route modules. Each one defined a router; I attach them
# all to the main app.
app.include_router(health.router)
app.include_router(model.router)
app.include_router(detect.router)


@app.get("/")
def root() -> dict:
    """Friendly landing message."""
    return {
        "name": "SPAI Backend",
        "version": "0.1.0",
        "docs": "/docs",
    }
