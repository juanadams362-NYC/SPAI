# v5 — making the detectors way better

## What we found (Nov 2026 audit of the shipped models)

| Model | Architecture | Reported mAP50 / mAP50-95 | Trained with |
|---|---|---|---|
| PPE `best.pt` (v3) | YOLOv8**n**, 3.0M params | 0.948 / 0.729 | defaults, 50 epochs, 640px |
| Instruments `instruments_best.pt` (v4) | YOLOv8**n**, 3.0M params | 0.921 / 0.649 | defaults, 50 epochs, 640px |

The headline numbers are in-distribution. On real frames the PPE model has one dominant failure:
**it labels the same physical hand twice.**

| Frame | Raw model output (conf ≥ 0.25) | What the app concluded |
|---|---|---|
| `images-18.jpeg` (one gloved hand + one bare hand) | hand 0.80, glove 0.73, **hand 0.61**, **hand 0.31**, **glove 0.28** | 5 boxes for 2 hands |
| `docs/.../pov_test_no_detections.jpg` (two gloved hands) | glove 0.90, **hand 0.74 (same box)**, glove 0.67 | **"PPE check failed"** while fully gloved |

A faint "glove" on a bare hand is worse: the contamination rule is `hand && !glove`, so a ghost glove can
hide a real bare hand.

**Root cause is the data, not just the model.** v2/v3 merged datasets by relabeling *every* box of a
source to one class (`merge_v2.py`: all glove-dataset boxes → glove, all EgoHands boxes → hand).
Gloved hands inside hand datasets were taught as "hand", and bare hands in glove photos were never
labeled at all. A nano model trained on that will hedge with both labels.

## What's already fixed (no retraining needed)

- **Glove/hand arbitration** in the backend (`app/inference/detector.py`) and the app
  (`DetectionService.resolvePPEOverlaps`): each region of the frame keeps only its most confident
  label (class-agnostic, IoU ≥ 0.5 or ≥ 60% containment). Both frames above now resolve correctly:
  `hand 0.80 + glove 0.73` and `glove 0.90 + glove 0.67` → **PPE passing**.
- **Instrument counts**: the tray detector now uses class-agnostic NMS, so one forceps can't be counted
  twice under two instrument names.
- **On-device instrument model** is rebuilt and actually committed (the `.gitignore` had been silently
  excluding its weights, so fresh clones couldn't build). It also uses class-agnostic NMS.

## The v5 retrain — what makes it "way better"

1. **Clean the labels first** — `audit_labels.py`
   ```bash
   python audit_labels.py /content/merged                                   # report contradictions
   python audit_labels.py /content/merged --fix --out /content/merged_clean # drop hand-on-glove duplicates
   python audit_labels.py /content/merged --model ../../backend/model/best.pt --conf 0.5
   ```
   The last command uses the current model to list **probable missing labels** (e.g. unlabeled bare
   hands in glove photos) and **label/model disagreements** as CSVs. Spend an hour in Roboflow fixing
   the top of those lists — that hour is worth more than any hyperparameter.

2. **Train a bigger, better-tuned model** — `train_v5.py`
   - YOLO11**s** (~9M params, still real-time on Vision Pro's Neural Engine and the backend CPU).
   - PPE: wider hue/saturation augmentation so purple/blue/black nitrile reads as *glove*, head-tilt
     rotation, slight perspective, occasional upside-down hands, 120 epochs with cosine LR.
   - Instruments: **960px** input for thin instruments, vertical flips for top-down trays, stronger
     brightness range for OR lighting, 150 epochs.
   ```bash
   python train_v5.py --task ppe --data /content/merged_clean/data.yaml \
       --baseline ../../backend/model/best.pt --export
   python train_v5.py --task instruments --data /content/ASTRA/data.yaml \
       --baseline ../../backend/model/instruments_best.pt --export
   ```

3. **Ship only if it wins.** `train_v5.py` evaluates the new and current model on the *same* split and
   prints a side-by-side table — including the PPE **double-label rate** (share of images where two
   classes land on one object; the current model scores 100% on the two frames above). It exits non-zero
   and says *"keep the current model"* unless mAP50-95 improves and the double-label rate doesn't get worse.

4. **Install** — copy from `runs/v5/<task>_v5/export/`:
   - `best.pt` → `backend/model/best.pt`, `instruments_best.pt` → `backend/model/instruments_best.pt`
   - `best.mlpackage` → `SPAI/best.mlpackage`, `instruments_best.mlpackage` → `SPAI/instruments_best.mlpackage`
     (keep the file names — Xcode generates the Swift classes `best` / `instruments_best` from them).

The notebook `../notebooks/spai_v5_training.ipynb` runs all of this on a free Colab T4
(about 1.5 h for PPE, 2 h for instruments).

## Data still worth adding (from the v3 plan, still open)

- ≥ 300 **nitrile** glove instances (purple, blue, black, white), labeled glove — the deployment gap.
- Bare hands photographed **from above at table height**, labeled hand.
- Hard negatives: empty trays, gowns, blue drapes, skin-tone objects — images with *no* labels teach
  the model when not to fire.
- A frozen **golden test set** (~100 frames from the actual SPD room / headset) that is never trained
  on. Pass it to `train_v5.py --split test` so every future model is judged on real conditions.

## Smoke test

`train_v5.py` and `audit_labels.py` were run end-to-end on a two-image dataset (1 epoch, CPU, starting
from the current weights): audit found the injected contradiction, `--fix` removed it, training,
side-by-side evaluation, model card and CoreML export all completed, and the gate correctly refused
the 1-epoch model.
