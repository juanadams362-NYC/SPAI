# v4 Data Plan — Tray State Detection

**Ticket:** SCRUM-73
**Goal:** Add tray-state detection to SPAI. The model should tell whether a
surgical tray is **empty** or **loaded** with instruments — not detect the
instruments themselves.

This is v4. It does NOT replace v3 (glove/hand) — it's a separate capability
that runs alongside it, or as a second model, TBD at integration time.

---

## Scope

**Two classes:**

- `empty_tray` — a tray with no instruments on it
- `loaded_tray` — a tray with instruments on it

That's it. We are deliberately NOT detecting individual instruments (scalpel,
forceps, etc.) — that's a much harder problem (small, shiny, overlapping metal)
and out of scope for the capstone timeline. Empty-vs-loaded gives a real
workflow signal without the instrument-detection rabbit hole.

**Why this matters for SPAI:** in sterile processing, knowing a tray's state is
useful context — an empty tray at a station means "ready to load," a loaded tray
means "ready to process / inspect." Pairs naturally with station tracking
(SCRUM-81): *tray detected + station marker = this station is active.*

---

## Data sourcing — Roboflow

Same approach that worked for v3: find existing datasets on Roboflow Universe,
download via API (free), merge, remap to our two classes, train on Colab.

### Search terms to try on Roboflow Universe

- "surgical tray"
- "surgical instruments tray"
- "instrument tray"
- "surgical kit"
- "operating room tray"
- "sterile tray"

### What to look for in a candidate dataset

- **Has trays clearly visible** (not just close-up instruments)
- **Both states represented** — ideally some empty trays AND some loaded ones.
  If a dataset only has loaded trays, we'll need a separate source for empties.
- **Decent image count** — aim for a few hundred minimum per class after merge
- **Varied angles / lighting** — top-down, angled, different trays

### Realistic expectation

Empty trays may be HARDER to find than loaded ones — most surgical datasets show
instruments, not bare trays. Backup plan if empties are scarce:

- Search "metal tray" / "kidney dish" / "medical tray empty" separately
- Worst case: photograph empty trays yourself (a metal tray is easy to source/mock)
  and label them — even 50-100 self-shot empties would help balance the classes

---

## Class remapping

However many classes the source datasets use, everything collapses to our two.
Same pattern as the v3 merge (where we mapped glove/hand variants down to 2
classes). Example logic, to be filled in once we see the actual datasets:

```
# Per source dataset, map their class IDs to ours:
# 0 = empty_tray, 1 = loaded_tray
#
# e.g. if a dataset has classes ['tray', 'tray_with_tools']:
#   tray            -> 0  (empty_tray)
#   tray_with_tools -> 1  (loaded_tray)
#
# if a dataset is ALL loaded trays (one class 'surgical_tray'):
#   surgical_tray   -> 1  (loaded_tray)
#
# empties sourced separately all map to -> 0
```

Unified `data.yaml`:
```
nc: 2
names: ['empty_tray', 'loaded_tray']
```

---

## Class balance — the thing to watch

The #1 risk for this model: **imbalanced classes.** If we end up with 2000 loaded
trays and 100 empty trays, the model will just learn to say "loaded" for
everything and look accurate on paper while being useless.

**Target:** roughly balanced — ideally within a 2:1 ratio between the two classes.
If empties are scarce, either source more, or downsample the loaded set to match.
Better to have 300 of each than 2000 loaded + 150 empty.

---

## Training (later session — NOT now)

When the data's ready, training reuses the exact pipeline from v3:

- Merge datasets in Colab, remap classes, write `data.yaml`
- `YOLO("yolov8n.pt")`, ~50 epochs, imgsz 640, batch 16, patience 15
- Train on free Colab T4 GPU (confirm GPU runtime, `device=0`)
- **The moment training finishes: save to Drive + download + commit to git**
  (the lesson from v3 — never let the model exist in only one place)
- Save weights to `model-training/runs/v4/weights/best.pt`

---

## Success criteria

- Both classes detected with reasonable confidence on held-out test images
- mAP50 in a usable range (v3 hit 0.948; tray state may be easier OR harder
  depending on data quality — empties especially)
- Model generalizes to trays it didn't train on (test-set detections, not just
  training images — the real generalization check)

---

## Open questions to resolve before training

1. **Are empty-tray images findable on Roboflow, or do we self-source them?**
   (Decide after searching — this is the biggest unknown.)
2. **One model or two?** Does v4 become its own model, or do we merge tray classes
   into the v3 glove/hand model for a single 4-class model? (Integration decision —
   a single model is simpler to serve but mixing very different object types can
   hurt accuracy. Lean toward separate models unless serving two is a problem.)
3. **How does tray state surface in the UI?** New panel? Part of the existing
   detection panel? (Frontend decision for a later ticket.)

---

## Next steps (in order)

1. Search Roboflow Universe with the terms above, find 1-3 candidate datasets
2. Check each for tray visibility + class balance (especially empties)
3. If empties are scarce, find a separate empty-tray source or plan to self-shoot
4. Note each dataset's download slug + class scheme (like we did for v3)
5. THEN (later session): merge, remap, train, save-everywhere, commit
