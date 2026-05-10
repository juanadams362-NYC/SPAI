# SPAI Backend API Plan

**Status:** Design only. No implementation yet.
**Sprint:** Week 2
**Author:** Juan

---

## Purpose

This doc plans the backend service that sits between the SPAI visionOS client (running on Apple Vision Pro) and the trained YOLOv8 model.

The backend's job is to:
1. Receive frames from the AVP client
2. Run the YOLOv8 model on each frame
3. Return detection results
4. Log workflow events for later compliance review

---

## Why a backend at all (vs on-device)

**On-device option:** Bundle the YOLOv8 model directly into the visionOS app via CoreML. Inference runs on AVP. No network needed.

**Backend option:** AVP sends frames to a server, server runs the model, returns results.

**Decision for v1:** Backend.

**Why:**
- Faster iteration. I can update the model on the server without resubmitting the AVP app.
- Easier debugging during development. Server logs are simpler than on-device logs.
- AVP compute is shared with rendering. Offloading inference frees that up.
- Allows multi-device scenarios later (instructor reviewing what a student is doing in real time).

**Future:** Once the model is stable, ship a CoreML version for on-device inference as fallback / privacy mode.

---

## Architecture sketch

```
AVP Client (visionOS)
   │
   │  HTTP POST  /api/detect
   │  body: frame image (JPEG, base64)
   ▼
Backend API (FastAPI or Express)
   │
   │  call
   ▼
Model Service (PyTorch/Ultralytics or ONNX runtime)
   │
   │  detections
   ▼
Backend API
   │
   │  HTTP 200
   │  body: { detections: [...], complianceStatus: "..." }
   ▼
AVP Client (renders overlays)
```

A separate event log database stores session events for review.

---

## API endpoints

### `POST /api/detect`

Submit a frame, get detections back.

**Request:**
```json
{
  "sessionId": "session_001",
  "frameId": "frame_00042",
  "image": "<base64-encoded JPEG>",
  "timestamp": "2026-05-10T19:32:00Z"
}
```

**Response:**
```json
{
  "sessionId": "session_001",
  "frameId": "frame_00042",
  "detections": [
    {
      "label": "glove",
      "confidence": 0.94,
      "bbox": [120, 85, 240, 210]
    }
  ],
  "complianceStatus": "COMPLIANT",
  "modelVersion": "spai_glove_detection_v1"
}
```

`complianceStatus` is derived by the backend from the detections + the current workflow step. Possible values:
- `COMPLIANT` — all expected objects present
- `WARNING` — something looks off but not critical
- `CONTAMINATION` — major compliance failure detected
- `UNKNOWN` — not enough info yet (e.g. session just started)

### `GET /api/model/status`

Health check. Tells the client what model version is loaded and whether the service is up.

**Response:**
```json
{
  "status": "ready",
  "modelVersion": "spai_glove_detection_v1",
  "loadedAt": "2026-05-10T18:00:00Z"
}
```

### `POST /api/session/:id/ai-alert`

Client tells the backend that a user-facing alert was raised. Used for logging.

**Request:**
```json
{
  "alertType": "MISSING_GLOVES",
  "message": "Bare hand detected in tray assembly area",
  "timestamp": "2026-05-10T19:33:00Z"
}
```

### `GET /api/session/:id/events`

Returns the full event log for a session. Used for after-action review (instructor reviewing a student's session).

**Response:**
```json
{
  "sessionId": "session_001",
  "events": [
    {
      "timestamp": "2026-05-10T19:32:00Z",
      "type": "DETECTION",
      "label": "glove",
      "confidence": 0.94
    },
    {
      "timestamp": "2026-05-10T19:33:00Z",
      "type": "ALERT",
      "alertType": "MISSING_GLOVES"
    }
  ]
}
```

---

## Tech stack (planned)

- **API framework:** FastAPI (Python). Same language as the model = simpler than juggling Python and Node.
- **Model serving:** Ultralytics for v1. ONNX runtime later for performance.
- **Database:** SQLite for v1 (single-file, zero setup). Postgres if multi-user becomes a need.
- **Hosting:** Local dev only for v1. Cloud (Render, Railway, or Fly.io) when needed for AVP testing.

---

## Compliance logic

Compliance is **derived**, not directly trained. The model detects objects (glove, hand, tray, etc). The backend takes those detections plus knowledge of which workflow step the user is on and decides whether the situation is compliant.

Example logic:
- Step = "tray assembly"
- Detections = `[{label: "hand", conf: 0.9}]` (no glove detected)
- → `complianceStatus: WARNING` ("Hand detected but no glove in tray assembly area")

This logic eventually becomes a finite state machine. v1 won't have FSM — just simple per-frame rules. FSM is v3+.

---

## What's NOT in this plan yet

- Authentication / user accounts (single-user dev mode for now)
- Real-time streaming (WebSockets)
- Multi-frame temporal logic (v3+ with FSM)
- Image storage / replay (deferred until needed)

---

## Implementation roadmap

| Sprint | Backend deliverable |
|--------|---------------------|
| Week 2 (this) | Design doc only (this file) |
| Week 3 | FastAPI skeleton: `/api/detect` returning hardcoded responses |
| Week 4 | Wire the actual YOLOv8 model into `/api/detect` |
| Week 5 | Add session event logging + SQLite |
| Week 6+ | FSM-based compliance logic |
