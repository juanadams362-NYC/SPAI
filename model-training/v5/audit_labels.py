#!/usr/bin/env python3
"""audit_labels.py — find (and optionally fix) the label problems behind glove/hand confusion.

Why this exists
---------------
The v3 PPE model labels one physical hand twice — "glove" and "hand" on the same spot —
and sometimes puts a faint "glove" on a bare hand. That comes from the data: v2/v3 were
built by relabeling *every* box of a source dataset to one class (all glove-dataset boxes
→ glove, all EgoHands boxes → hand). Gloved hands inside hand datasets were therefore
taught as "hand", and bare hands in glove photos were never labeled at all.

What it does
------------
1. Contradictions: any image where a "glove" and a "hand" box cover the same object
   (IoU ≥ 0.5, or ≥ 60% of the smaller box inside the larger). → contradictions.csv
2. --fix --out DIR: writes a cleaned copy of the dataset where, for each contradiction,
   the hand box is dropped (a hand box on top of a glove box *is* a gloved hand).
3. --model best.pt: model-assisted review. Flags confident predictions with no matching
   label (probable missing labels, e.g. unlabeled bare hands) → missing_labels.csv, and
   labels the model confidently calls the other class → class_disagreements.csv.

Usage
-----
    python audit_labels.py datasets/merged
    python audit_labels.py datasets/merged --fix --out datasets/merged_clean
    python audit_labels.py datasets/merged --model ../../backend/model/best.pt --conf 0.5

The dataset must use the standard YOLO layout: images/{train,val,test} + labels/{...}.
"""

from __future__ import annotations

import argparse
import csv
import shutil
from pathlib import Path

IMG_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
SPLITS = ("train", "val", "valid", "test")
IOU_T, CONTAIN_T = 0.5, 0.6


def yolo_to_xyxy(cx: float, cy: float, w: float, h: float) -> tuple[float, float, float, float]:
    return (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)


def overlap(a, b) -> tuple[float, float]:
    """(IoU, containment-of-smaller) for two xyxy boxes."""
    ix = max(0.0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0.0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    if inter <= 0:
        return 0.0, 0.0
    area_a = max(0.0, a[2] - a[0]) * max(0.0, a[3] - a[1])
    area_b = max(0.0, b[2] - b[0]) * max(0.0, b[3] - b[1])
    union = area_a + area_b - inter
    return (inter / union if union > 0 else 0.0), inter / max(1e-9, min(area_a, area_b))


def read_labels(path: Path) -> list[tuple[int, float, float, float, float]]:
    rows = []
    if not path.exists():
        return rows
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) < 5:
            continue
        rows.append((int(float(parts[0])), *map(float, parts[1:5])))
    return rows


def write_labels(path: Path, rows) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(f"{c} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}" for c, cx, cy, w, h in rows))


def find_image(images_dir: Path, stem: str) -> Path | None:
    for ext in IMG_EXTS:
        for candidate in (images_dir / f"{stem}{ext}", images_dir / f"{stem}{ext.upper()}"):
            if candidate.exists():
                return candidate
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dataset", type=Path)
    ap.add_argument("--glove-id", type=int, default=0)
    ap.add_argument("--hand-id", type=int, default=1)
    ap.add_argument("--fix", action="store_true", help="write a cleaned copy (requires --out)")
    ap.add_argument("--out", type=Path)
    ap.add_argument("--model", type=Path, help="current model for model-assisted review")
    ap.add_argument("--conf", type=float, default=0.5, help="confidence for model-assisted flags")
    args = ap.parse_args()

    root: Path = args.dataset
    if args.fix and not args.out:
        ap.error("--fix needs --out (the original dataset is never modified)")
    report_dir = args.out or root
    report_dir.mkdir(parents=True, exist_ok=True)

    model = None
    if args.model:
        from ultralytics import YOLO
        model = YOLO(str(args.model))

    contradictions, missing, disagreements = [], [], []
    stats = {"images": 0, "boxes": 0, "contradiction_images": 0, "hand_boxes_dropped": 0}

    for split in SPLITS:
        labels_dir, images_dir = root / "labels" / split, root / "images" / split
        if not images_dir.exists():
            continue
        for image in sorted(p for p in images_dir.iterdir() if p.suffix.lower() in IMG_EXTS):
            stats["images"] += 1
            label_path = labels_dir / f"{image.stem}.txt"
            rows = read_labels(label_path)
            stats["boxes"] += len(rows)
            boxes = [yolo_to_xyxy(*r[1:]) for r in rows]

            drop: set[int] = set()
            for i, (ci, *_ ) in enumerate(rows):
                for j in range(i + 1, len(rows)):
                    cj = rows[j][0]
                    if {ci, cj} != {args.glove_id, args.hand_id}:
                        continue
                    iou, contain = overlap(boxes[i], boxes[j])
                    if iou >= IOU_T or contain >= CONTAIN_T:
                        contradictions.append([split, image.name, round(iou, 3), round(contain, 3)])
                        drop.add(i if ci == args.hand_id else j)
            if drop:
                stats["contradiction_images"] += 1
                stats["hand_boxes_dropped"] += len(drop)

            if args.fix:
                out_img = args.out / "images" / split / image.name
                out_img.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(image, out_img)
                write_labels(args.out / "labels" / split / f"{image.stem}.txt",
                             [r for k, r in enumerate(rows) if k not in drop])

            if model is not None:
                result = model(str(image), conf=args.conf, verbose=False)[0]
                h, w = result.orig_shape
                for b in result.boxes:
                    pc, conf = int(b.cls[0]), float(b.conf[0])
                    x1, y1, x2, y2 = b.xyxy[0].tolist()
                    pred = (x1 / w, y1 / h, x2 / w, y2 / h)
                    best_iou, best_cls = 0.0, None
                    for (gc, *_), gbox in zip(rows, boxes):
                        iou, _ = overlap(pred, gbox)
                        if iou > best_iou:
                            best_iou, best_cls = iou, gc
                    name = result.names[pc]
                    if best_iou < 0.3:
                        missing.append([split, image.name, name, round(conf, 3), [round(v, 4) for v in pred]])
                    elif best_cls is not None and best_cls != pc and best_iou >= 0.5:
                        disagreements.append([split, image.name, result.names.get(best_cls, best_cls), name,
                                              round(conf, 3), round(best_iou, 3)])

    def dump(name, header, rows):
        path = report_dir / name
        with path.open("w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(header)
            writer.writerows(rows)
        return path

    p1 = dump("contradictions.csv", ["split", "image", "iou", "containment"], contradictions)
    print(f"Scanned {stats['images']} images / {stats['boxes']} boxes")
    print(f"  glove+hand contradictions: {len(contradictions)} pairs in {stats['contradiction_images']} images → {p1}")
    if args.fix:
        print(f"  cleaned copy written to {args.out} ({stats['hand_boxes_dropped']} duplicate hand boxes dropped)")
        for yaml_file in root.glob("*.yaml"):
            target = args.out / yaml_file.name
            try:
                import yaml
                cfg = yaml.safe_load(yaml_file.read_text()) or {}
                if "path" in cfg:
                    cfg["path"] = str(args.out.resolve())   # point the copy at the cleaned data
                target.write_text(yaml.safe_dump(cfg, sort_keys=False))
            except ImportError:
                shutil.copy2(yaml_file, target)
    if model is not None:
        p2 = dump("missing_labels.csv", ["split", "image", "predicted", "conf", "box_xyxy_norm"], missing)
        p3 = dump("class_disagreements.csv", ["split", "image", "label", "model_says", "conf", "iou"], disagreements)
        print(f"  probable missing labels: {len(missing)} → {p2}")
        print(f"  label/model disagreements: {len(disagreements)} → {p3}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
