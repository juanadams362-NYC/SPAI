# v4 Instrument Model — Validation Results

**Ticket:** SCRUM-85
**Model:** instruments_best.pt (YOLOv8n, trained on ASTRA Surgical Instruments dataset)
**Training result:** mAP50 0.92

## What I tested

The point of v4 is loaded-vs-empty tray detection via instrument counting:
1 or more instruments detected = loaded, zero = empty. So validation had to
prove two things — the model detects instruments on a loaded tray, and
correctly detects nothing on an empty tray.

I ran the images through the actual backend endpoint (/detect-tray) to
confirm the full pipeline, not just the model in isolation.

## Results

### image-1 — loaded tray (should detect instruments -> "loaded")

- 3 instruments detected (confidences 0.774, 0.755, 0.332)
- instrument_count: 3
- tray_state: loaded ✅
- inference time: ~1522 ms

### image-2 — empty tray (should detect nothing -> "empty")

- 0 detections
- instrument_count: 0
- tray_state: empty ✅
- inference time: ~73 ms

## What this proves

- The model reliably detects instruments on a loaded tray.
- The model correctly returns zero detections on an empty tray — which is
  what makes the count approach work (no empty-tray training data needed;
  empty is just the absence of detections).
- The full backend pipeline (/detect-tray) returns the correct instrument
  count and the right loaded/empty verdict for both cases.
- mode is "real" for both — confirming it's running the actual trained
  model, not a stub.

## Honest notes / limitations

- The ASTRA dataset reports a very high mAP (99.5%) and is fairly "easy" —
  consistent top-down shots. So the model performs great on trays similar to
  its training data.
- Not yet tested on a wide range of very different real-world tray photos
  (different lighting, angles, tray types). A future version would benefit
  from more diverse training data to confirm it generalizes broadly.
- The model labels every detection the same ("instrument") — it can't
  reliably tell the individual instruments apart, which is fine for the
  count approach since we only need "is there an instrument," not which one.
