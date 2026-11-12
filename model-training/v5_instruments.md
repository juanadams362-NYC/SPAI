# v5 — Instrument identification that actually names instruments

## What was wrong with v4

`backend/model/instruments_best.pt` (v4) was meant to tell six instruments
apart. Scored with `scripts/eval_instruments.py` on ASTRA's own untouched test
photos, it:

- **found** 99% of instruments, and
- **named every single one "Adson Dressing Forceps"**.

Its correct-name rate of 18% is just the share of test instruments that
really are Adson forceps. That is why the backend used to relabel everything
as a generic "instrument", and why the app, once it started showing the
model's names, showed one name for everything.

Two separate problems:

1. **The classifier never learned.** The model came out knowing
   "instrument" but not which one. The checkpoint doesn't record why; a
   dataset export that collapsed the six classes into one would produce
   exactly this, and would also explain the 92% mAP recorded in it.
2. **The data is one scene.** All 464 ASTRA photos are from one fixed overhead
   camera, of one tray, on one sheet of blue paper, with instruments lying
   mostly upright. A model trained on that has never seen an instrument at an
   angle, in a hand, or against anything but blue paper.

## What v5 does

ASTRA's labels are oriented boxes, so each instrument can be cut out cleanly.
`scripts/build_instruments_v5.py` cuts them out and composites them into new
images where everything that was constant now varies: rotation (any angle),
scale, perspective, background (photos and procedural), lighting, blur and
noise, and hand-like shapes over part of the instrument.

| Split | Contents |
| --- | --- |
| train | 325 ASTRA photos + 2,000 synthetic + 150 instrument-free negatives |
| val | 69 ASTRA photos + 200 synthetic |
| test_astra | 70 untouched ASTRA photos |
| test_handheld | 400 handheld-style composites |

ASTRA's own split is respected end to end: cutouts from test photos are only
used to build test images, and test backgrounds are never used in training.

Training (`scripts/train_instruments_v5.py`) also turns on full rotation and
vertical flips, which Ultralytics leaves off by default, and weights the
class loss more heavily because the classes are fine-grained.

## Results

Share of instruments given the correct name (`scripts/eval_instruments.py`):

| Test set | v4 | v5 |
| --- | --- | --- |
| Real tray photos (70 images, 176 instruments) | 18.2% | **88.6%** |
| Handheld-style (400 images, 541 instruments) | 5.0% | **71.5%** |

Per instrument, v5:

| Instrument | Tray | Handheld |
| --- | --- | --- |
| Adson Dressing Forceps | 78.8% | 82.0% |
| Babcock Tissue Forceps | 96.9% | 69.9% |
| Halsted Mosquito Forceps | 93.8% | 47.7% |
| Mayo-Hegar Needle Holder | 96.8% | 72.1% |
| Operating Scissors | 100.0% | 86.0% |
| Scalpel Handle No. 3 | 60.9% | 66.2% |

Trained on a 4-core CPU: YOLOv8n at 448px, 14 epochs then 18 more from the
best checkpoint (about 2 hours). It was still improving when it stopped; a
longer run on a GPU at 640px should do better, especially on the thin
instruments (Adson forceps, scalpel handle).

## What this does not prove

**No real photo of an instrument held in a gloved hand was available** for
training or testing. `test_handheld` is synthetic: real instrument cutouts,
but painted hand shapes and composited backgrounds. It shows the model is no
longer tied to the tray scene. It does not guarantee the same numbers through
the headset camera.

The way to close that gap is real data: 20–30 photos per instrument, held in
gloved hands at the actual bench, labelled and added to the training set.
`build_instruments_v5.py --backgrounds` also accepts folders of your own
instrument-free photos (the bench, the sink, gloved hands), which is the
cheapest improvement available.

## Reproduce

    # 1. Get ASTRA (CC BY 4.0) in YOLO-OBB format
    #    https://universe.roboflow.com/astra-juyrg/astra-surgical-instruments-erspj
    # 2. Build the dataset
    python scripts/build_instruments_v5.py --astra ASTRA_DIR --out v5_dataset \
        --backgrounds my_bench_photos/
    # 3. Train (Colab T4: ~25 min at the defaults)
    python scripts/train_instruments_v5.py --data v5_dataset/data.yaml
    # 4. Score it the way a user experiences it
    python scripts/eval_instruments.py --weights runs/v5_instruments/weights/best.pt \
        --images v5_dataset/test_handheld/images --labels v5_dataset/test_handheld/labels
    # 5. Ship it
    cp runs/v5_instruments/weights/best.pt ../backend/model/instruments_best.pt
    python scripts/export_instruments_coreml.py runs/v5_instruments/weights/best.pt
    #    then copy instruments_best.mlpackage over SPAI/instruments_best.mlpackage

ASTRA Surgical Instruments is licensed CC BY 4.0; credit the dataset if you
publish the model.
