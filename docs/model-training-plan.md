# SPAI Model Training Plan

**Project:** SPAI — Sterile Processing AI
**Author:** Juan
**Sprint:** Week 2 — AI/Model Training Focus
**Last updated:** May 2026

---

## 1. Purpose

This document is the plan for the computer vision side of SPAI. It explains what the model is supposed to do, why I chose this approach for the first version, what data I'm using, and how the training pipeline is set up.

The goal is not to build the final SPAI model in one sprint. The goal this week is to:

1. Stand up a working YOLOv8 training pipeline end-to-end in Google Colab.
2. Train a first model on a narrow task (glove detection) that I can actually evaluate.
3. Have real metrics, real outputs, and a clear plan for how this scales toward sterile processing workflow compliance.

---

## 2. Scope of v1

**What v1 is:**
A single-class YOLOv8 object detection model that detects gloves in first-person camera frames.

**What v1 is NOT:**
- Not yet medical/sterile-glove specific (training data is construction PPE — see Section 4).
- Not yet a workflow compliance system.
- Not yet integrated with the visionOS app or backend.
- Not yet doing hand keypoints, instrument detection, or contamination detection.

This narrow scope is intentional. The point of v1 is to validate that the full pipeline (data → training → evaluation → exportable model) works before adding complexity.

---

## 3. Why glove detection first

Glove detection was chosen as the v1 target because:

- **It's directly relevant to compliance.** Whether a tech is wearing gloves is one of the most basic sterile processing checks.
- **It's a single, well-defined visual class.** A glove either is or isn't in frame. This avoids the ambiguity of trying to classify entire workflow states on day one.
- **Public datasets exist in YOLO format.** I can train without spending the first sprint on data labeling.
- **It's a starting point, not an endpoint.** Once a glove detector works, the same pipeline extends to bare hands, trays, instruments, and packaging.

---

## 4. Dataset

**Source:** `shlokraval/ppe-dataset-yolov8` on Kaggle (Roboflow export of "Personal Protective Equipment Combined Model").

**Original classes (14):** Fall-Detected, Gloves, Goggles, Hardhat, Ladder, Mask, NO-Gloves, NO-Goggles, NO-Hardhat, NO-Mask, NO-Safety Vest, Person, Safety Cone, Safety Vest.

**Filtered to v1 classes (1):** `glove` (remapped from source class id 1).

**Split sizes after filtering:**
- Train: 30,765 images (~1,500 with glove annotations, rest serve as background examples)
- Val: 8,814 images
- Test: 4,423 images

**Important caveat:** This is a **construction PPE** dataset, not a medical one. Construction gloves are visually different from nitrile/surgical gloves used in sterile processing. v1 is a baseline to validate the pipeline. v2 will fine-tune on medical PPE data (planned source: `skaarface/medical-personal-protective-equipment-images`) and/or self-labeled AVP footage.

Background images (no glove labels) are kept rather than deleted. YOLOv8 uses these as negative examples, which helps reduce false positives.

---

## 5. Model architecture

**Model:** YOLOv8n (nano variant) from Ultralytics.

**Why YOLOv8n:**
- Smallest model in the YOLOv8 family (~3M parameters, ~6 MB).
- Fast enough to potentially run on-device in the long term (Apple Vision Pro has compute constraints).
- Easy to export to ONNX / CoreML for Apple platforms.
- Pretrained on COCO, so transfer learning works well even with limited domain data.

Larger variants (YOLOv8s, YOLOv8m) are options if accuracy from the nano variant isn't sufficient. Will evaluate after v1 baseline.

---

## 6. Training pipeline

**Environment:** Google Colab, T4 GPU (free tier).

**Pipeline steps:**

1. Upload Kaggle API credentials (`kaggle.json`) to Colab.
2. Download PPE dataset via Kaggle CLI.
3. Unzip into `/content/datasets/ppe_raw/`.
4. Filter labels to keep only the `Gloves` class, remap class id to 0.
5. Copy filtered data into `/content/datasets/glove_detection/` with YOLOv8-standard structure:
   ```
   glove_detection/
     images/train, images/val, images/test
     labels/train, labels/val, labels/test
     data.yaml
   ```
6. Write `data.yaml` pointing to the splits and declaring class names.
7. Load YOLOv8n pretrained weights.
8. Train.
9. Validate on the val split. Inspect plots, metrics, sample predictions.
10. Export model to ONNX (planned, for future backend serving).

**Hyperparameters (v1 baseline):**
- Epochs: 15 (with early stopping `patience=5`)
- Image size: 640
- Batch size: 16
- Optimizer: AdamW (auto-selected by Ultralytics)

---

## 7. Smoke test results

Before committing to a long training run, I ran a 3-epoch smoke test to confirm the pipeline works.

**Smoke test results (3 epochs):**
- Precision: 0.761
- Recall: 0.845
- mAP50: 0.773
- mAP50-95: 0.354

This confirmed:
- The pipeline runs end-to-end without errors.
- The model is actually learning (mAP50 well above random).
- Plateau behavior was already visible by epoch 3, which informed dropping the planned 25 epochs down to 15 with early stopping for the full run.

---

## 8. How v1 connects to the rest of SPAI

The trained model produces detections in the form:

```json
{
  "label": "glove",
  "confidence": 0.94,
  "bbox": [x, y, w, h]
}
```

These detections become inputs to:

- **Backend** — a planned model service that receives frames from the visionOS app and returns detection JSON.
- **Workflow compliance logic** — a future finite state machine that tracks which workflow step the user is on and whether gloves are present when they should be.
- **visionOS overlays** — floating AR labels positioned over detected objects in the user's real-world view via AVP.

None of those downstream components are built yet. v1 is the foundation.

---

## 9. Roadmap

**v1 (this sprint):** Glove detection. Construction PPE data. Baseline metrics. Pipeline validated.

**v2:** Add `hand` class (likely via EgoHands dataset — first-person bbox annotations match AVP camera perspective). Add `bare_hand` (negative compliance signal).

**v3:** Fine-tune on medical PPE / self-labeled SPD footage. Reduces domain gap between construction PPE and sterile processing context.

**v4:** Add tray and instrument detection. Expand class set toward full workflow coverage.

**v5+:** Integrate detections with a finite state machine for workflow step tracking. Add YOLOv8-pose for hand keypoints (separate model). Eventually integrate with backend + visionOS client.

---

## 10. Open questions / risks

- **Domain gap.** Construction gloves vs. medical gloves is a real visual difference. Need to measure how badly v1 generalizes before relying on it.
- **First-person camera angle.** Training data is mostly third-person/surveillance angles. AVP footage will be first-person. Will need self-labeled samples to validate.
- **No SPD-specific contamination data exists publicly.** Contamination detection will require either synthetic data or self-labeled footage.
- **Compute budget.** Colab free tier disconnects after idle periods. Longer training runs may require Colab Pro or a different environment.
