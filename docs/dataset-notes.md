# SPAI Dataset Notes

Working notes on datasets evaluated and used for SPAI model training. Updated each sprint.

---

## Datasets in use (v1)

### `shlokraval/ppe-dataset-yolov8` — ACTIVE

- **Source:** Kaggle, Roboflow export
- **Original project:** Personal Protective Equipment Combined Model (Roboflow Universe)
- **Format:** YOLOv8 (Roboflow export). Already split into train/valid/test.
- **License:** CC BY 4.0
- **Original classes:** 14 (Fall-Detected, Gloves, Goggles, Hardhat, Ladder, Mask, NO-Gloves, NO-Goggles, NO-Hardhat, NO-Mask, NO-Safety Vest, Person, Safety Cone, Safety Vest)
- **Filtered to:** 1 class (`glove`, remapped from source class id 1)
- **Used for:** v1 glove detection training
- **Splits after filtering:**
  - Train: 30,765 images (~1,500 with glove annotations after filtering, rest = background)
  - Val: 8,814 images
  - Test: 4,423 images
- **Caveat:** Construction PPE, not medical. Gloves in this dataset are work gloves (leather, fabric), not surgical/nitrile.

---

## Datasets evaluated, not yet used

### `skaarface/medical-personal-protective-equipment-images`

- **Status:** Not yet inspected.
- **Potential use:** v2 fine-tuning. Closer to actual sterile processing visual domain.
- **Next action:** Inspect format (YOLO-ready vs needs conversion) before sprint 3.

### `riondsilva21/hand-keypoint-dataset-26k`

- **Status:** Set aside for now.
- **Why not v1:** This is keypoint data (21 landmarks per hand), not bounding boxes. Would require training a YOLOv8-pose model, which is a separate model head from detection. Can't be combined with bbox data in a single training run.
- **Future plan:** Train a separate YOLOv8-pose model on this for hand gesture / position analysis. Useful for detecting handling motions (e.g., is the tech grasping an instrument correctly).

### EgoHands

- **Status:** Strong candidate for v2.
- **Why:** First-person hand bounding box annotations. The AVP camera is also first-person, so the camera perspective matches.
- **Plan:** Add as a second class (`hand`) alongside `glove` in a v2 training run.

### `dilavado/labeled-surgical-tools`, `qhasiinnovationsota/surgicaltool-object-detection`

- **Status:** v3+ candidates.
- **Use:** Instrument detection in tray assembly step.

### MVTec AD, NEU surface defect, DAGM 2007

- **Status:** Future inspection step.
- **Use:** Potential for instrument defect / damage detection during inspection workflow step.

### `realtimear/hand-wash-dataset`

- **Status:** Maybe useful for decontamination workflow.
- **Use:** Possibly an action recognition / temporal model rather than detection.

---

## Decisions made and why

**Decision:** Start with a single class (`glove`) instead of multi-class.
**Reason:** Smaller scope = faster to debug. If the pipeline breaks, the bug isn't from class confusion. Once v1 works, additional classes get added incrementally.

**Decision:** Use construction PPE data for v1 even though it's not medical.
**Reason:** Roboflow-exported format means zero conversion work. Medical PPE dataset format is unknown until inspected. Goal of v1 is pipeline validation, not state-of-the-art accuracy. Medical fine-tuning is planned.

**Decision:** Keep background images (no glove labels) instead of dropping them.
**Reason:** YOLOv8 uses these as negative examples and they help reduce false positives. Recommended in Ultralytics docs.

**Decision:** Rename Roboflow's `valid` folder to `val` during the copy step.
**Reason:** YOLOv8's default `data.yaml` convention expects `val`. Avoids needing custom yaml paths.

---

## Data quality notes

- Image quality varies (Roboflow combined dataset = mix of sources).
- Some glove annotations are partial (only fingertips visible, etc.). This is realistic and shouldn't hurt training.
- Lighting varies significantly (indoor warehouse, outdoor construction). This is actually useful for generalization.

---

## Known data gaps for SPAI

These are the gaps between public datasets and what SPAI actually needs. Will need to address with self-labeled data or synthetic data:

1. **Sterile processing department settings.** No public dataset is filmed in an SPD.
2. **Surgical glove visuals.** Nitrile/latex blue gloves are very different from construction PPE gloves.
3. **First-person AVP perspective.** Most public PPE data is third-person/surveillance.
4. **Workflow step labels.** No public data labels "this is the decontamination step" vs "this is tray assembly."
5. **Contamination events.** No public dataset of "tech touched contaminated surface, then sterile surface" sequences.
6. **Inter-object relationships.** Public data labels objects, not the spatial/temporal relationships between them.

Most of these gaps will require self-labeling for the final SPAI system.
