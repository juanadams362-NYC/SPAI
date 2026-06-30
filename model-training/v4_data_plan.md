# v4 Data Plan — Tray State via Instrument Detection

**Ticket:** SCRUM-82 (research/select), SCRUM-84 (train), SCRUM-86 (integrate)
**Goal:** Tell whether a surgical tray is empty or loaded — by detecting
instruments and counting them, NOT by classifying the tray directly.

## The approach (and why it changed)

Original plan was to train a model with two whole-tray classes (empty_tray /
loaded_tray). Two problems with that: empty-tray training images are scarce,
and whole-tray state is a vaguer thing for a model to learn.

Better approach landed on: **detect instruments, count them in code.**
- The model detects surgical instruments (it's trained on a 6-instrument set).
- App code counts the detections.
- **1 or more instruments = loaded tray. Zero = empty tray.**

Why this is better:
- **Solves the empty-data problem.** "Empty" = the detector found nothing.
  No empty-tray training images needed — absence of detection IS the signal.
- **The model does one simple thing** (find instruments), which is more
  reliable than asking it to judge overall tray state.
- **Loaded/empty logic lives in code**, so the threshold is tunable instantly
  without retraining.
- **Bonus:** because we keep all 6 instrument classes (instead of collapsing
  to one), the model identifies SPECIFIC instruments for free — a head start
  on a future named-instrument version (v5).

## Dataset

**Source:** ASTRA Surgical Instruments (Roboflow)
- Workspace/project: `astra-juyrg/astra-surgical-instruments-erspj`, version 12
- 480 images total — 408 train, 72 test (no valid split; we use test as val)
- Top-down camera angle (matches how an SPD tech views a tray)
- Instruments in varied positions across images (real variety)
- Includes completely empty trays (act as negative examples — teaches the
  model not to false-positive on an empty tray)

**6 classes (kept as-is, not remapped):**
Adson Dressing Forceps, Babcock Tissue Forceps, Halsted Mosquito Forceps,
Mayo Hegar Needle Holder, Operating Scissors, Scalpel Handle 3

**Reported metrics (treat with healthy skepticism):** the dataset page lists
99.5% mAP — suspiciously high, likely an "easy" dataset (clean top-down shots).
The real test is how it does on fresh images, which is why SCRUM-85 validates
on images outside this dataset, not just the dataset's own numbers.

## Training

Same pipeline as the v3 retrain, but simpler (one dataset, no remap):
- Train YOLOv8n on the dataset as-is, all 6 classes, ~50 epochs, Colab T4
- One fix needed: the dataset has no `valid` split, so point `val` at the
  `test` folder in data.yaml (and use absolute paths — Roboflow's relative
  paths don't resolve correctly in Colab)
- The moment training finishes: save to Drive + download + commit (v3 lesson)
- Weights to model-training/runs/v4_instruments/

## Loaded / empty logic

Decided rule: **detections >= 1 → loaded, detections == 0 → empty.**
Robust (no frame-to-frame flicker from a high threshold), matches real
meaning. Lives in backend/app code, not the model.

## Integration (SCRUM-86)

The instrument model is SEPARATE from the existing glove/hand model — they do
different jobs (PPE check vs tray state). Plan: a new backend endpoint
(e.g. /detect-tray) that runs the instrument model, counts detections, and
returns both the raw detections AND the loaded/empty verdict. Keeps the two
models cleanly separated, consistent with the existing route structure.

## Validation (SCRUM-85)

Don't trust the 99.5% mAP. Test the trained model on 10-15 tray images it
never trained on — ideally some sourced/shot fresh. Record what it gets right
and wrong, especially: does it correctly find nothing on a genuinely empty
tray, and does it detect instruments on a loaded one. That proves the
loaded/empty logic actually works in practice.
