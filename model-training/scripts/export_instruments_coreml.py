"""
Export trained instrument weights to the Core ML package the app loads.

    python export_instruments_coreml.py runs/v5_instruments/weights/best.pt --imgsz 448

Writes instruments_best.mlpackage next to the weights. Copy it over
SPAI/instruments_best.mlpackage. NMS is baked in, so Vision hands the app
finished VNRecognizedObjectObservation boxes with the instrument names as
labels — which is what OnDeviceDetector expects.

Use the same --imgsz the model was trained at.
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from ultralytics import YOLO


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("weights")
    ap.add_argument("--imgsz", type=int, default=448)
    ap.add_argument("--name", default="instruments_best", help="package name the app's generated class is called")
    args = ap.parse_args()

    exported = Path(YOLO(args.weights).export(format="coreml", nms=True, imgsz=args.imgsz))
    target = exported.with_name(f"{args.name}.mlpackage")
    if exported != target:
        if target.exists():
            shutil.rmtree(target)
        exported.rename(target)
    print(f"Core ML package: {target}")


if __name__ == "__main__":
    main()
