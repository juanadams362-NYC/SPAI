# v3 Dataset Plan

**Date:** 2026-06-02 (Week 9)
**Status:** Planning — precedes data sourcing, labeling, and training
**Basis:** v2 out-of-distribution evaluation (see `SPAI_v2_eval` notebook)

## Goal

Close the gaps measured in the v2 evaluation by fine-tuning on targeted
additional data, while preserving v2's strong in-distribution hand performance.
Classes stay fixed and in order: `0: glove`, `1: hand`.

## Gaps to close (from v2 eval)

| # | Gap | Evidence | Priority |
|---|-----|----------|----------|
| 1 | Medical / nitrile gloves unrecognized | yellow leather & rubber gloves -> 0 detections | High |
| 2 | Bare hands in flat / top-down poses missed | splayed desk hand -> 0 detections | High |
| 3 | Limited deployment realism (table work, clinical) | training data is casual indoor / EgoHands-style | Medium |

In-distribution hands (curled, active) already score 76-86%. Do **not**
over-collect these — adding more reinforces what already works and wastes
labeling effort.

## Sourcing strategy (hybrid)

Most data comes pre-labeled from public datasets. Only the nitrile-specific gap
requires custom collection and manual labeling.

| Source | Covers | Effort | Notes |
|--------|--------|--------|-------|
| Roboflow "Gloves and bare hands detection" (Dolphin, ~868 imgs) | Gap 2 + glove variety | Low — pre-labeled | Two-class match (glove + bare hand) |
| Roboflow hand-detection sets | Gap 2 pose variety | Low — pre-labeled | Optional top-up |
| Custom nitrile batch (~40 web-sourced, self-labeled) | Gap 1 | Medium — manual label | Not available off-the-shelf |

Industrial PPE glove datasets are deliberately **excluded** — they reinforce the
existing gap rather than closing it.

## Volume target

~150 effective new training images. Instances (labeled boxes) matter more than
raw image count. Allocation skews toward Gap 1 (nitrile), since it is the
deployment-critical gap and the only manually labeled portion.

## Labeling

- **Tool:** Roboflow Annotate (web, free) — same platform as the imported
  datasets, allowing a single merged export.
- **Export format:** YOLOv8.
- **Class consistency rule:** all merged data must map to exactly
  `{0: glove, 1: hand}` in that order. Mismatched class indices cause silent
  training errors. Verify `data.yaml` before training.

## Acceptance criteria (v3 data "done")

- [ ] Merged dataset exports cleanly in YOLOv8 format
- [ ] `data.yaml` confirms two classes in correct order
- [ ] Nitrile gloves represented (>= 30 instances)
- [ ] Flat / top-down bare-hand poses represented
- [ ] Train / val / test split applied (e.g. 80 / 10 / 10)

## Out of scope for v3

- SPD instruments and trays (deferred to v4)
- Real SPD-environment footage (hardware testing phase)
