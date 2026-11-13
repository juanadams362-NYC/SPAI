# SPAI Backend

FastAPI service that runs YOLO inference for the SPAI visionOS app.

## Status

- Two models, loaded once at startup and warmed up so the first frame is fast:
  - `model/best.pt` — PPE (glove / hand)
  - `model/instruments_best.pt` — six named surgical instruments
- If a weights file is missing, that detector runs in stub mode and returns
  fixed fake detections, so the app can be developed without the model.

## Endpoints

| Route | What it does |
| --- | --- |
| `GET /` | Service metadata |
| `GET /health`, `/health/stats`, `/health/dashboard` | Liveness, JSON stats, HTML status page |
| `GET /model/status` | PPE model state |
| `POST /detect` | Gloves and hands in one image |
| `POST /detect/batch` | Same, for up to 16 images |
| `POST /detect-tray` | Named instruments, tray loaded/empty, and the identified instrument |
| `POST /analyze` | **Everything for one frame in one upload**: PPE, named instruments (each flagged `held` or not), tray state, and the identified instrument |
| `GET /instruments`, `/instruments/{key}` | Reference card per instrument: what it is, how to recognise it, what to inspect |
| `GET/PATCH /settings` | Confidence thresholds, including `identify_threshold` |
| `POST /compliance/event`, `/compliance/reset`, `GET /compliance/state` | Workflow state machine |
| `POST /ask` | Ask SPAI — grounded in the station script and, when an instrument is named, its reference card |

Interactive docs at `/docs`.

### Instrument identification

`/analyze` and `/detect-tray` return an `identified` object for the one
instrument the user is most likely showing:

- an instrument with a hand or glove on it beats one lying on the bench;
- below `identify_threshold` (default 0.60) it is reported as a generic
  "Instrument" with `certain: false` rather than a name SPAI isn't sure of.

The names come from the label list inside the weights file. The knowledge
base is `app/instruments.py`; the app carries a matching copy in
`SPAI/InstrumentCatalog.swift` for on-device fallback — change both together.

## The pilot platform

Beyond detection, the backend is what makes SPAI usable by a class:

| Route | Who | What it does |
| --- | --- | --- |
| `GET /instructor` | Instructor | The dashboard: roster, results, score trends, where the class slips, run reports, protocol editor |
| `GET /learners` | Headset | The roster, for the sign-in list |
| `GET /protocol` | Headset | The institution's station scripts, count sheets and scoring rubric |
| `PUT /sessions/{id}` | Headset | Upload a finished run; the server scores it. Safe to retry |
| `GET /privacy` | Anyone | What this server stores, in plain language |
| `/compliance/*` | Headset | Workflow state, now kept **per headset** via the `X-SPAI-Session` header |

Records live in a SQLite file at `backend/data/spai.db` (override with
`SPAI_DB`). Camera frames are never written anywhere.

### Before real students use it

Set these environment variables on the server:

| Variable | Purpose |
| --- | --- |
| `SPAI_API_KEY` | Shared key the headsets send. Enter the same value in SPAI Settings |
| `SPAI_INSTRUCTOR_PIN` | PIN for the instructor dashboard |
| `SPAI_SECRET` | Any long random string; keeps instructors signed in across restarts |
| `SPAI_RETENTION_DAYS` | Optional. Delete runs this many days after they end |
| `GEMINI_API_KEY` | For Ask SPAI |

Without the first two the server runs open and says so on the dashboard and
at startup.

**Storage must be persistent.** The database is a file. A host that wipes
the disk on restart (a free Hugging Face Space does) will lose every run.
For a pilot, use a host with a persistent volume and point `SPAI_DB` and
`SPAI_PROTOCOL` at it, and serve over HTTPS.

### A sample class for demos

    python -m app.seed_demo            # 12 invented learners, ~50 runs
    python -m app.seed_demo --clear

Sample learners are flagged in the database and labelled in the dashboard.

## Tests

    cd backend
    pytest -q

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
