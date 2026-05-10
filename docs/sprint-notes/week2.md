# Week 2 Sprint Notes — AI/Model Training Focus

**Sprint dates:** May 5–10, 2026
**Focus:** AI / model training and backend planning
**Hours logged:** ~30

---

## Sprint goal

> This week I'm focusing on the AI/model training and backend side of SPAI. I already chose the datasets I want to use, so now I'm putting in time to organize them, set up the YOLOv8 training workflow, prepare the first glove/hand detection model, plan the backend connection, and document everything clearly in GitHub. My goal is to have real training pipeline progress and enough proof of work for my milestone.

---

## What got done

### 1. Dataset selection and prep (SCRUM-19)

- Evaluated all six datasets I had identified (PPE, hand keypoints, hand washing, surgical tools, EgoHands, defect detection).
- Decided to start with `shlokraval/ppe-dataset-yolov8` for v1 because it's already in YOLOv8 format and has a `Gloves` class.
- Filtered the original 14-class dataset down to single-class (`glove`) for v1 simplicity. Construction PPE caveat documented in `docs/dataset-notes.md`.
- Final split sizes: 30,765 train / 8,814 val / 4,423 test.

**Evidence:**
- `docs/dataset-notes.md` — full evaluation of every dataset
- `docs/model-training-plan.md` — Section 4 explains the v1 dataset choice

### 2. Colab YOLOv8 pipeline setup (SCRUM-21, SCRUM-22)

- Set up Google Colab with T4 GPU runtime.
- Installed Ultralytics, configured Kaggle API auth.
- Downloaded and unzipped the PPE dataset.
- Wrote a Python script to filter labels to glove-only and remap class id to 0.
- Built `data.yaml` for YOLOv8.

**Evidence:**
- `model-training/notebooks/spai_glove_detection_yolov8_starter.ipynb`

### 3. Smoke test training run

3-epoch smoke test to validate the pipeline before committing to a long run.

| Metric | Value |
|--------|-------|
| Precision | 0.761 |
| Recall | 0.845 |
| mAP50 | 0.773 |
| mAP50-95 | 0.354 |

### 4. Full training run

- 15 epochs with early stopping `patience=5`.
- Dropped from the originally-planned 25 epochs because the smoke test showed the model was plateauing.
- Total training time: 2.24 hours on a Colab T4 GPU.

**Final results vs smoke test:**

| Metric | Smoke (3 ep) | Full (15 ep) |
|--------|--------------|--------------|
| Precision | 0.761 | **0.839** |
| Recall | 0.845 | **0.871** |
| mAP50 | 0.773 | **0.899** |
| mAP50-95 | 0.455 | **0.455** |

mAP50 of 0.899 means the model is detecting gloves accurately on the test split with minimal false positives. mAP50-95 = 0.455 shows there's room to improve box-edge precision — likely needs more epochs or a larger model (YOLOv8s/m) to close that gap.

**Confusion matrix breakdown:**
- 757 correctly detected gloves (true positives)
- 101 missed gloves (false negatives)
- 142 false positive detections

### 5. Out-of-distribution test: POV domain gap

After the in-distribution test set looked good, I tested the model on something it hadn't seen: **first-person / POV images** of gloved hands (sourced from Google Images, downloaded for evaluation only).

I ran inference at two confidence thresholds:
- `conf=0.25` (moderate) → **0 detections out of 4 POV images**
- `conf=0.10` (very permissive) → **0 detections out of 4 POV images**

This is a measurable, not theoretical, domain gap. The model goes from ~0.9 mAP50 on construction-style PPE images to 0% on POV images. Even with the confidence threshold pulled all the way down to 0.10, the model isn't weakly recognizing gloves in POV frames — it's genuinely seeing nothing it classifies as a glove.

**Why this matters:** SPAI will run on Apple Vision Pro, which is by definition a first-person camera. v1 in its current state would not work for SPAI's actual use case. This justifies the v2 plan (add EgoHands data — first-person bbox annotations) and v3 plan (fine-tune on medical/SPD footage) as critical, not optional.

**Why it's not a surprise:** The training data was construction-site surveillance and worker photography, almost entirely third-person/elevated camera angles. The model overfit to that perspective. This is exactly the kind of result that domain transfer literature predicts.

### 6. Documentation

- `docs/model-training-plan.md` — full plan covering scope, architecture, dataset, pipeline, roadmap.
- `docs/dataset-notes.md` — dataset evaluations and decisions.
- `model-training/README.md` — folder-level intro and reproduction steps.

### 7. Backend planning (SCRUM-8)

API design doc only this sprint, no code. Implementation is week 3.

See `docs/backend-api-plan.md` for the full spec.

---

## Screenshots / evidence

Files saved in `docs/sprint-notes/week2-screenshots/`:

1. **`results.png`** — training curves over 15 epochs. All four losses drop, all four metrics climb. Visible drop at epoch 5–6 is mosaic augmentation turning off (`close_mosaic=10` default).
2. **`confusion_matrix.png`** — 757 correct glove detections, 101 missed, 142 false positives.
3. **`BoxPR_curve.png`** — precision-recall curve with mAP@0.5 = 0.899 marked.
4. **`sample_prediction_industrial.jpg`** — model running on a real test image: industrial packing facility ("PP-2 PACKING"), two gloves detected with confidences 0.60 and 0.47. Shows v1 generalizes to industrial process environments.
5. **`pov_test_no_detections.jpg`** — example POV image. Zero glove detections even at `conf=0.10`. Evidence of the domain gap.

---

## What didn't get done / is still in progress

- ONNX export of the model (deferred to next sprint — v1 isn't deployment-ready until v2 closes the POV domain gap anyway).
- Backend code (only the design doc this sprint).
- visionOS/UI work (intentionally deferred per professor's guidance).

---

## Key learnings

- **Smoke tests save time.** The 3-epoch smoke run caught that the model plateaus fast. If I'd committed to 25 epochs blindly I'd have wasted ~2 hours of GPU.
- **Background images matter.** YOLOv8 keeps unlabeled images as negative examples. Originally I considered deleting them — turns out keeping them helps reduce false positives.
- **In-distribution metrics ≠ real-world performance.** Going from 0.899 mAP50 on the test set to 0% detection on POV images was the biggest lesson of the sprint. Headline metrics can mask a model that's useless for the actual deployment context.
- **mAP50 vs mAP50-95 tells you something specific.** The gap between mine (0.899 → 0.455) means the model knows *where* gloves are but its box edges aren't tight. That's the dfl_loss component — would improve with more epochs or a bigger model.
- **Roboflow exports save days of work.** Zero time spent on label conversion.
- **Colab sessions time out.** Lost an environment partway through, had to rebuild. Lesson: keep setup commands grouped at the top of the notebook so re-running is fast.

---

## Decisions made

- Use construction PPE for v1 (over medical PPE) because it's YOLO-ready out of the box.
- Single class (`glove`) for v1, not multi-class. Smaller scope = easier debugging.
- 15 epochs with early stopping, not 25 fixed.
- Defer hand detection to v2. Keypoint dataset can't combine with bbox dataset in one training run anyway.
- POV domain gap is now the highest-priority issue heading into v2.

---

## Plan for next sprint

- **Highest priority:** Add EgoHands dataset (first-person bbox annotations) — directly addresses the POV domain gap measured in Section 5.
- Inspect `skaarface/medical-personal-protective-equipment-images` for v3 fine-tuning planning.
- Begin backend implementation (the design is already done, see `docs/backend-api-plan.md`).
- Self-label a small SPD-specific validation set so I can measure SPAI-context performance separately from training data.
