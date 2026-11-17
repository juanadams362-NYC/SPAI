# v5 — A way better glove/hand (PPE) detector

Instruments already have their v5 (see [`v5_instruments.md`](v5_instruments.md): correct names went
from 18% to 88.6% on real tray photos). This is the matching plan for the other model, the one that
decides whether a hand is gloved, which drives the contamination alarm.

## What we found in the shipped PPE model

| Model | Architecture | Reported mAP50 / mAP50-95 | Trained with |
|---|---|---|---|
| `backend/model/best.pt` (v3, also `SPAI/best.mlpackage`) | YOLOv8**n**, 3.0M params | 0.948 / 0.729 | defaults, 50 epochs, 640px |

Those numbers are in-distribution. On real frames, the model's dominant failure is that
**it labels the same physical hand twice.**

| Frame | Raw model output (conf ≥ 0.25) |
|---|---|
| `images-18.jpeg` (one gloved hand + one bare hand) | hand 0.80, glove 0.73, **hand 0.61**, **hand 0.31**, **glove 0.28**: five boxes for two hands |
| `docs/.../pov_test_no_detections.jpg` (two gloved hands) | glove 0.90, **hand 0.74 (same box)**, glove 0.67 |

**The root cause is in the data.** v2/v3 merged datasets by relabeling *every* box of a source to
one class (`scripts/merge_v2.py`: every glove-dataset box became glove, every EgoHands box became
hand). Gloved hands inside hand datasets were taught as "hand", and bare hands in glove photos were
never labeled. A nano model trained on that data hedges with both labels.

## What's already handled in the app and backend (no retraining)

- **Safety verdict.** `DetectionService.resolveHands` treats heavily overlapping boxes as one hand
  and lets the more confident label decide. A tie goes to glove, and a bare hand only counts at
  0.5 confidence or higher.
- **Clean boxes.** `DetectionService.resolvePPEOverlaps` (app) and `resolve_overlaps` (backend)
  keep one box per hand before anything is stored or drawn. They also remove a partial box that
  sits mostly inside a stronger one (IoU 0.42 on the frame above, under the 0.5 same-hand line).
  The backend gathers candidates from 0.15 so faint duplicates are caught before thresholding.
  With the shipped weights, both frames above now come back as `hand 0.80 + glove 0.73` and
  `glove 0.90 + glove 0.67`.

These steps clean up after the model. v5 fixes the model itself.

## The v5 retrain

1. **Clean the labels first**: `scripts/audit_ppe_labels.py`
   ```bash
   python audit_ppe_labels.py /content/merged                                   # report contradictions
   python audit_ppe_labels.py /content/merged --fix --out /content/merged_clean # drop hand-on-glove duplicates
   python audit_ppe_labels.py /content/merged --model ../../backend/model/best.pt --conf 0.5
   ```
   The last command uses the shipped model to list **probable missing labels** (for example,
   unlabeled bare hands in glove photos) and **label/model disagreements** as CSVs. An hour fixing
   the top of those lists in Roboflow is worth more than any hyperparameter.

2. **Train a bigger, better-tuned model**: `scripts/train_ppe_v5.py`
   - YOLO11**s** (~9M params, still real-time on Vision Pro's Neural Engine and the backend CPU).
   - A wider hue and saturation range so purple, blue, black and white nitrile all read as glove.
     Also head-tilt rotation, slight perspective, occasional upside-down hands, and 120 epochs with
     cosine LR.
   ```bash
   python train_ppe_v5.py --data /content/merged_clean/data.yaml \
       --baseline ../../backend/model/best.pt --export
   ```

3. **Ship it only if it wins.** The script evaluates the new and shipped models on the *same*
   split and prints them side by side, including the **double-label rate**: the share of images
   where two classes land on one object. The shipped model scores 100% on the two frames above.
   Unless mAP50-95 improves and the double-label rate doesn't get worse, the script exits non-zero
   and says *"keep the current model"*.

4. **Install** from `runs/v5/ppe_v5/export/`: copy `best.pt` to `backend/model/best.pt` and
   `best.mlpackage` to `SPAI/best.mlpackage`. Keep the name, because Xcode generates the Swift
   class `best` from it.

The notebook `notebooks/spai_ppe_v5_training.ipynb` runs all of this on a free Colab T4 in about
1.5 hours.

## Data still worth adding

- At least 300 **nitrile** glove instances (purple, blue, black, white), labeled glove. This is
  the deployment gap from the v3 plan.
- Bare hands photographed **from above at table height**, labeled hand.
- Hard negatives with *no* labels, such as gowns, blue drapes and skin-tone objects, so the model
  learns when not to fire.
- A frozen **golden test set** of about 100 frames from the real SPD room and headset, never used
  for training. Pass it with `--split test` so every future model is judged on real conditions.

## Smoke test

Both scripts ran end to end on a two-image dataset (1 epoch on CPU, starting from the shipped
weights):
- The audit found an injected contradiction, and `--fix` removed it.
- Training, the side-by-side evaluation, the model card and the CoreML export all completed.
- The gate correctly refused the 1-epoch model.
