# SPAI Backend

FastAPI service that runs YOLO inference for the SPAI visionOS app.

## Status

- Routes: /health, /model/status, /detect all live
- Inference mode: stub until v2 model is trained
- Auto-switches to real inference once best.pt exists

## Endpoints

- GET /              - service metadata
- GET /health        - liveness check
- GET /model/status  - model loaded state
- POST /detect       - upload image, get detections

Interactive docs at /docs.

## Run locally

    cd backend
    pip install -r requirements.txt
    uvicorn app.main:app --reload --port 8000

## Architecture

The detector is loaded once at server startup and reused across requests.
Routes never touch the model directly. They call Detector.detect(), which
picks stub or real mode based on whether best.pt exists on disk.

In stub mode, /detect returns fixed fake detections so the visionOS
frontend can develop against a working API contract before v2 trains.

In real mode, /detect runs YOLO. The JSON shape stays identical.
