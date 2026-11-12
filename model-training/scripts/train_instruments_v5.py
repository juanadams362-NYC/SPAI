"""
Train the v5 instrument model on the re-staged dataset.

Build the dataset first with build_instruments_v5.py, then:

    python train_instruments_v5.py --data /path/to/v5_dataset/data.yaml

On a Colab T4 use the defaults (640px, 60 epochs — about 25 minutes).
On a CPU, pass --imgsz 480 --epochs 20 or so and expect an hour or two.

The augmentation settings matter as much as the data. v4 used Ultralytics'
defaults, which never rotate an image or flip it vertically — fine for
street scenes, wrong for an instrument that can be held at any angle.
"""
from __future__ import annotations

import argparse

from ultralytics import YOLO


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", required=True)
    ap.add_argument("--weights", default="yolov8n.pt", help="starting weights")
    ap.add_argument("--epochs", type=int, default=60)
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--fraction", type=float, default=1.0, help="share of the training set to use")
    ap.add_argument("--project", default="runs")
    ap.add_argument("--name", default="v5_instruments")
    ap.add_argument("--device", default=None)
    ap.add_argument("--resume", action="store_true",
                    help="continue an interrupted run; pass its last.pt as --weights")
    args = ap.parse_args()

    model = YOLO(args.weights)
    if args.resume:
        # Picks up epoch, optimizer state and every setting from the checkpoint.
        model.train(resume=True)
        return
    model.train(
        data=args.data,
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        workers=args.workers,
        fraction=args.fraction,
        project=args.project,
        name=args.name,
        device=args.device,
        exist_ok=True,
        patience=15,
        # An instrument has no "right way up".
        degrees=180,
        flipud=0.5,
        fliplr=0.5,
        # Distance and framing vary a lot between a tray and an outstretched hand.
        scale=0.6,
        translate=0.15,
        perspective=0.0005,
        # Steel takes on the colour of whatever lights it.
        hsv_h=0.03,
        hsv_s=0.6,
        hsv_v=0.5,
        mosaic=1.0,
        close_mosaic=5,
        # Classes are fine-grained (a needle holder is nearly a hemostat), so
        # weight getting the name right more heavily than the default 0.5.
        cls=1.0,
        plots=True,
    )


if __name__ == "__main__":
    main()
