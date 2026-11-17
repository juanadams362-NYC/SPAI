#!/usr/bin/env python3
"""train_ppe_v5.py — train a stronger glove/hand (PPE) detector and prove it beats the shipped one.

What changes vs the shipped PPE model (v3: YOLOv8n, default settings):
  • Bigger backbone: YOLO11s (~9M params) instead of YOLOv8n (~3M). Still real-time on
    Vision Pro's Neural Engine and on the backend CPU.
  • Augmentation tuned to the job: a wider hue/saturation range so purple, blue, black and
    white nitrile all read as "glove", head-tilt rotation, slight perspective, and
    occasional upside-down hands for top-down views.
  • Longer schedule with cosine LR and a late mosaic shut-off.
  • A built-in gate: the new and shipped models are evaluated on the SAME split, including
    the glove/hand double-label rate that made gloved users read as "PPE check failed".

Instruments have their own v5 pipeline (see ../v5_instruments.md).

Typical Colab run (T4), after cleaning the labels with audit_ppe_labels.py:
    python train_ppe_v5.py --data /content/merged_clean/data.yaml \
        --baseline ../../backend/model/best.pt --export
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

PRESETS: dict[str, dict] = {
    "ppe": dict(
        model="yolo11s.pt", imgsz=640, epochs=120, patience=30, batch=16,
        hsv_h=0.03, hsv_s=0.75, hsv_v=0.45, degrees=15.0, translate=0.1, scale=0.5,
        shear=2.0, perspective=0.0005, flipud=0.1, fliplr=0.5, mosaic=1.0, mixup=0.1,
        close_mosaic=15, cos_lr=True,
    ),
}


def overlap(a, b) -> tuple[float, float]:
    ix = max(0.0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0.0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    if inter <= 0:
        return 0.0, 0.0
    area_a = (a[2] - a[0]) * (a[3] - a[1])
    area_b = (b[2] - b[0]) * (b[3] - b[1])
    union = area_a + area_b - inter
    return (inter / union if union > 0 else 0.0), inter / max(1e-9, min(area_a, area_b))


def double_label_rate(model, image_dir: Path, conf: float = 0.25, limit: int = 400) -> float:
    """Share of images where the model puts two different classes on the same object."""
    images = sorted(p for p in image_dir.iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png"})[:limit]
    if not images:
        return float("nan")
    hits = 0
    for image in images:
        boxes = model(str(image), conf=conf, verbose=False)[0].boxes
        preds = [(int(b.cls[0]), b.xyxy[0].tolist()) for b in boxes]
        if any(ci != cj and (lambda o: o[0] >= 0.5 or o[1] >= 0.6)(overlap(bi, bj))
               for k, (ci, bi) in enumerate(preds) for (cj, bj) in preds[k + 1:]):
            hits += 1
    return hits / len(images)


def evaluate(weights: str, data: str, split: str, imgsz: int, device: str | None, task: str) -> dict:
    from ultralytics import YOLO
    model = YOLO(weights)
    m = model.val(data=data, split=split, imgsz=imgsz, device=device, plots=False, verbose=False)
    out = {
        "mAP50": float(m.box.map50),
        "mAP50-95": float(m.box.map),
        "precision": float(m.box.mp),
        "recall": float(m.box.mr),
        "per_class_mAP50-95": {model.names[int(c)]: float(ap) for c, ap in zip(m.box.ap_class_index, m.box.maps[m.box.ap_class_index])},
    }
    if task == "ppe":
        import yaml
        cfg = yaml.safe_load(Path(data).read_text())
        base = Path(cfg.get("path", Path(data).parent))
        if not base.is_absolute():
            base = (Path(data).parent / base).resolve()
        split_dir = cfg.get(split) or cfg.get("val")
        image_dir = Path(split_dir) if Path(split_dir).is_absolute() else base / split_dir
        if image_dir.exists():
            out["double_label_rate"] = double_label_rate(model, image_dir)
    return out


def print_comparison(new: dict, old: dict | None) -> bool:
    keys = ["mAP50", "mAP50-95", "precision", "recall", "double_label_rate"]
    print("\n" + "=" * 64)
    print(f"{'metric':22s}{'current':>12s}{'v5':>12s}{'delta':>12s}")
    print("-" * 64)
    better = True
    for k in keys:
        if k not in new:
            continue
        nv = new[k]
        ov = old.get(k) if old else None
        if ov is None:
            print(f"{k:22s}{'—':>12s}{nv:>12.3f}")
            continue
        delta = nv - ov
        print(f"{k:22s}{ov:>12.3f}{nv:>12.3f}{delta:>+12.3f}")
        if k == "mAP50-95" and delta < 0:
            better = False
        if k == "double_label_rate" and delta > 0.01:
            better = False
    print("=" * 64)
    if old:
        print("VERDICT:", "v5 is better — ship it" if better else "v5 is NOT better — keep the current model")
    return better


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--task", choices=PRESETS, default="ppe")
    ap.add_argument("--data", required=True, help="YOLO data.yaml")
    ap.add_argument("--model", help="starting weights (default: preset, e.g. yolo11s.pt)")
    ap.add_argument("--epochs", type=int)
    ap.add_argument("--imgsz", type=int)
    ap.add_argument("--batch", type=int)
    ap.add_argument("--device", default=None, help="e.g. 0, cpu, mps")
    ap.add_argument("--baseline", help="current weights to compare against (same split)")
    ap.add_argument("--split", default="val", help="split used for the comparison")
    ap.add_argument("--project", default="runs/v5")
    ap.add_argument("--name", default=None)
    ap.add_argument("--fraction", type=float, default=1.0, help="train on a fraction (smoke tests)")
    ap.add_argument("--export", action="store_true", help="export best.pt + CoreML (.mlpackage, NMS)")
    args = ap.parse_args()

    from ultralytics import YOLO

    hyp = dict(PRESETS[args.task])
    start = args.model or hyp.pop("model")
    hyp.pop("model", None)
    for key in ("epochs", "imgsz", "batch"):
        if getattr(args, key):
            hyp[key] = getattr(args, key)
    name = args.name or f"{args.task}_v5"

    print(f"Training {args.task} from {start} with {json.dumps(hyp)}")
    model = YOLO(start)
    model.train(data=args.data, project=args.project, name=name, exist_ok=True,
                device=args.device, fraction=args.fraction, plots=True, **hyp)

    best = Path(args.project) / name / "weights" / "best.pt"
    if not best.exists():
        print(f"training finished but {best} is missing", file=sys.stderr)
        return 1

    new_metrics = evaluate(str(best), args.data, args.split, hyp["imgsz"], args.device, args.task)
    old_metrics = None
    if args.baseline:
        old_metrics = evaluate(args.baseline, args.data, args.split, hyp["imgsz"], args.device, args.task)
    better = print_comparison(new_metrics, old_metrics)

    out_dir = Path(args.project) / name / "export"
    out_dir.mkdir(parents=True, exist_ok=True)
    card = {"task": args.task, "start_weights": start, "hyperparameters": hyp,
            "v5": new_metrics, "current": old_metrics, "better": better}
    (out_dir / "model_card.json").write_text(json.dumps(card, indent=2))

    if args.export:
        target = "best.pt"
        shutil.copy2(best, out_dir / target)
        exported = YOLO(str(best)).export(format="coreml", nms=True, imgsz=hyp["imgsz"])
        package = Path(exported)
        final = out_dir / "best.mlpackage"
        if final.exists():
            shutil.rmtree(final)
        shutil.move(str(package), final)
        print(f"\nExported to {out_dir}:")
        print(f"  {target}            → copy to backend/model/{target}")
        print(f"  {final.name}  → replace SPAI/{final.name} (keep the file name: the Swift class is generated from it)")
        print("  model_card.json      → metrics for the record")
    return 0 if better or not args.baseline else 2


if __name__ == "__main__":
    raise SystemExit(main())
