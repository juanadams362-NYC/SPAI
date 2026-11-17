"""
Score an instrument model the way a user experiences it.

mAP is the standard detection metric, but it doesn't answer the question a
trainee asks: "when I hold one up, does it say the right name?" This script
answers that directly. For every labelled instrument in a test set it takes
the model's most confident overlapping prediction and reports:

  found      the model put a box on it at all
  named      ...and the box carries the correct instrument name
  confusion  which names it gave instead (a model that calls everything
             "Adson Dressing Forceps" shows up as one full column)

Usage
-----
    python eval_instruments.py --weights best.pt --images DIR/images --labels DIR/labels
"""
from __future__ import annotations

import argparse
import glob
import json
import os

import numpy as np
from ultralytics import YOLO


def iou(a, b) -> float:
    x0, y0, x1, y1 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    inter = max(x1 - x0, 0) * max(y1 - y0, 0)
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / union if union > 0 else 0.0


def evaluate(weights: str, images: str, labels: str, conf: float, imgsz: int, min_iou: float) -> dict:
    model = YOLO(weights)
    names = [model.names[i] for i in sorted(model.names)]
    n = len(names)
    # confusion[true][predicted]; the extra column is "not found".
    confusion = np.zeros((n, n + 1), dtype=int)
    false_alarms = 0
    files = sorted(glob.glob(f"{images}/*"))

    for start in range(0, len(files), 32):
        batch = files[start:start + 32]
        for path, result in zip(batch, model(batch, conf=conf, imgsz=imgsz, verbose=False)):
            h, w = result.orig_shape
            truth = []
            label_path = os.path.join(labels, os.path.splitext(os.path.basename(path))[0] + ".txt")
            for line in open(label_path) if os.path.exists(label_path) else []:
                p = line.split()
                if len(p) != 5:
                    continue
                cx, cy, bw, bh = (float(v) for v in p[1:])
                truth.append((int(p[0]), [(cx - bw / 2) * w, (cy - bh / 2) * h, (cx + bw / 2) * w, (cy + bh / 2) * h]))

            preds = [(float(b.conf[0]), int(b.cls[0]), b.xyxy[0].tolist()) for b in result.boxes]
            preds.sort(reverse=True)
            used = set()
            for cls, box in truth:
                match = next((i for i, (_, _, pb) in enumerate(preds) if i not in used and iou(box, pb) >= min_iou), None)
                if match is None:
                    confusion[cls, n] += 1
                else:
                    used.add(match)
                    confusion[cls, preds[match][1]] += 1
            false_alarms += len(preds) - len(used)

    total = int(confusion.sum())
    found = int(confusion[:, :n].sum())
    named = int(np.trace(confusion[:, :n]))
    return {
        "weights": weights,
        "images": len(files),
        "instruments": total,
        "found_pct": round(100 * found / max(total, 1), 1),
        "named_pct": round(100 * named / max(total, 1), 1),
        "named_when_found_pct": round(100 * named / max(found, 1), 1),
        "false_alarms_per_image": round(false_alarms / max(len(files), 1), 2),
        "per_class_named_pct": {names[i]: round(100 * confusion[i, i] / max(confusion[i].sum(), 1), 1) for i in range(n)},
        "predicted_name_share_pct": {names[j]: round(100 * confusion[:, j].sum() / max(found, 1), 1) for j in range(n)},
        "confusion": confusion.tolist(),
        "names": names,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--weights", required=True)
    ap.add_argument("--images", required=True)
    ap.add_argument("--labels", required=True)
    ap.add_argument("--conf", type=float, default=0.25)
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--iou", type=float, default=0.5)
    ap.add_argument("--json", help="write the full result here")
    args = ap.parse_args()

    r = evaluate(args.weights, args.images, args.labels, args.conf, args.imgsz, args.iou)
    if args.json:
        json.dump(r, open(args.json, "w"), indent=1)
    print(f"{r['instruments']} instruments in {r['images']} images")
    print(f"  found            {r['found_pct']}%")
    print(f"  correctly named  {r['named_pct']}%   ({r['named_when_found_pct']}% of those found)")
    print(f"  false alarms     {r['false_alarms_per_image']} per image")
    print("  correctly named, by instrument:")
    for name, pct in r["per_class_named_pct"].items():
        print(f"    {name:28s} {pct}%")
    print("  share of all names given (even = healthy, one big = collapsed):")
    for name, pct in r["predicted_name_share_pct"].items():
        print(f"    {name:28s} {pct}%")


if __name__ == "__main__":
    main()
