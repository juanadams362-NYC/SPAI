#!/usr/bin/env python3
"""merge_v2.py - combine glove + hand into one two-class YOLOv8 dataset for v2."""

from __future__ import annotations
import shutil
import sys
from pathlib import Path

IMG_EXTS = {".jpg", ".jpeg", ".png"}
SOURCES = [
    ("glove_detection", 0, "gl"),
    ("egohands_yolo",   1, "eh"),
]


def resolve_paths():
    here = Path(__file__).resolve().parent
    datasets = here.parent / "datasets"
    dst = datasets / "v2_combined"
    return datasets, dst


def copy_split(src_root, dst_root, split, new_class_id, prefix):
    src_images = src_root / "images" / split
    src_labels = src_root / "labels" / split
    if not src_images.exists():
        return (0, 0)
    dst_images = dst_root / "images" / split
    dst_labels = dst_root / "labels" / split
    dst_images.mkdir(parents=True, exist_ok=True)
    dst_labels.mkdir(parents=True, exist_ok=True)
    n_img = 0
    n_lbl = 0
    for img in src_images.iterdir():
        if img.suffix.lower() not in IMG_EXTS:
            continue
        new_name = f"{prefix}_{img.name}"
        shutil.copy(img, dst_images / new_name)
        n_img += 1
        lbl_src = src_labels / f"{img.stem}.txt"
        lbl_dst = dst_labels / f"{prefix}_{img.stem}.txt"
        if lbl_src.exists():
            new_lines = []
            for line in lbl_src.read_text().splitlines():
                parts = line.split()
                if len(parts) < 5:
                    continue
                parts[0] = str(new_class_id)
                new_lines.append(" ".join(parts))
            lbl_dst.write_text("\n".join(new_lines))
            n_lbl += 1
        else:
            lbl_dst.touch()
    return (n_img, n_lbl)


def main():
    datasets, dst = resolve_paths()
    if dst.exists():
        print(f"removing existing {dst}")
        shutil.rmtree(dst)
    missing = []
    for src_name, _, _ in SOURCES:
        src = datasets / src_name
        if not src.exists():
            missing.append(src_name)
    if missing:
        print("ERROR: missing source datasets:", file=sys.stderr)
        for name in missing:
            print(f"  {datasets / name}", file=sys.stderr)
        return 1
    totals = {}
    for src_name, class_id, prefix in SOURCES:
        src_root = datasets / src_name
        print(f"\nMerging {src_name} -> class {class_id}")
        for split in ("train", "val"):
            n_img, n_lbl = copy_split(src_root, dst, split, class_id, prefix)
            key = f"{src_name}:{split}"
            totals[key] = (n_img, n_lbl)
            print(f"  {split:5}  images: {n_img}  labels: {n_lbl}")
    yaml_text = (
        f"path: {dst.resolve()}\n"
        "train: images/train\n"
        "val: images/val\n"
        "\n"
        "nc: 2\n"
        "names: ['glove', 'hand']\n"
    )
    (dst / "data.yaml").write_text(yaml_text)
    print(f"\nWrote {dst / 'data.yaml'}")
    train_total = sum(n for k, (n, _) in totals.items() if k.endswith(":train"))
    val_total = sum(n for k, (n, _) in totals.items() if k.endswith(":val"))
    print(f"\nDone. v2 dataset assembled at {dst}")
    print(f"  total train images: {train_total}")
    print(f"  total val images:   {val_total}")
    return 0


if __name__ == "__main__":
    sys.exit(main())