# SPAI — Model Training

This folder contains everything related to training the computer vision models behind SPAI.

## What's here

```
model-training/
├── notebooks/
│   └── spai_glove_detection_yolov8_starter.ipynb   # Colab training notebook
├── datasets/
│   └── glove_detection/                            # Generated locally, not committed (too large)
├── configs/
│   └── glove_detection_data.yaml                   # YOLOv8 dataset config
└── README.md                                       # This file
```

Larger documentation lives in [`docs/`](../docs/):
- [Model Training Plan](../docs/model-training-plan.md) — the overall strategy
- [Dataset Notes](../docs/dataset-notes.md) — datasets evaluated and used

## Current status (v1)

| Item | Status |
|------|--------|
| YOLOv8 pipeline set up in Colab | Done |
| Glove dataset prepared (PPE, filtered to single class) | Done |
| Smoke test training (3 epochs) | Done — mAP50 0.77 |
| Full training run (15 epochs) | In progress |
| Model results review | Pending |
| ONNX export |  Pending |

## How to reproduce

1. Open `notebooks/spai_glove_detection_yolov8_starter.ipynb` in Google Colab.
2. Set runtime to T4 GPU (Runtime → Change runtime type).
3. Run cells top to bottom. You will need:
   - A Kaggle account
   - A `kaggle.json` API token (Settings → API → Create Legacy API Key on kaggle.com)
4. The notebook will download the dataset, filter to glove-only, train, and validate.

Training takes ~75 min on a T4 GPU. The Colab tab must stay open or the session will time out.

## Model architecture

- **Base:** YOLOv8n (nano, ~3M params)
- **Pretrained on:** COCO
- **Classes (v1):** 1 (`glove`)
- **Input size:** 640x640

## Datasets

v1 trains on `shlokraval/ppe-dataset-yolov8` from Kaggle, filtered to keep only the `Gloves` class.

This is construction PPE, not medical. See [Dataset Notes](../docs/dataset-notes.md) for the full reasoning and the planned path to medical-domain fine-tuning in v2+.

## Roadmap

- **v1** Glove detection (in progress)
- **v2** Add `hand` class via EgoHands dataset
- **v3** Fine-tune on medical PPE data
- **v4** Add tray and instrument classes
- **v5+** Integrate detections with FSM for workflow compliance + visionOS overlays

See [Model Training Plan](../docs/model-training-plan.md) for details.
