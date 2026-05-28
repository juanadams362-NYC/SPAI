#!/usr/bin/env python3
"""build_gloves.py - build local glove-only YOLOv8 dataset from Kaggle PPE source."""

from __future__ import annotations
import shutil
import subprocess
import sys
from pathlib import Path

GLOVE_SRC_ID = 1
KAGGLE_DATASET = "shlokraval/ppe-dataset-yolov8"
SPLIT_MAP = {"train": "train", "valid": "val", "test": "test"}


def resolve_paths():
    here = Path(__file__).resolve().parent
    model_training = here.parent
    datasets = model_training / "datasets"
    raw = datasets / ".cache" / "ppe_raw"
    dst = datasets / "glove_detection"
    return raw, dst, datasets


def kaggle_download(zip_target):
    zip_target.parent.mkdir(parents=True, exist_ok=True)
    print(f"[1/4] Downloading {KAGGLE_DATASET}...")
    subprocess.run(
        ["kaggle", "datasets", "download", "-d", KAGGLE_DATASET],
        cwd=zip_target.parent,
        check=True,
    )
    expected_zip = zip_target.parent / "ppe-dataset-yolov8.zip"
    if not expected_zip.exists():
        raise FileNotFoundError(f"expected {expected_zip} after kaggle download")
    return expected_zip


def unzip(zip_path, raw_dir):
    if raw_dir.exists():
        shutil.rmtree(raw_dir)
    raw_dir.mkdir(parents=True, exist_ok=True)
    print(f"[2/4] Unzipping into {raw_dir}...")
    subprocess.run(["unzip", "-q", str(zip_path), "-d", str(raw_dir)], check=True)


def filter_and_remap(raw_dir, dst):
    print(f"[3/4] Filtering to gloves-only, remapping class id to 0...")
    counts = {}
    for src_split, dst_split in SPLIT_MAP.items():
        src_images = raw_dir / src_split / "images"
        src_labels = raw_dir / src_split / "labels"
        if not src_images.exists() or not src_labels.exists():
            print(f"  skipping {src_split} (missing in source)")
            continue
        out_images = dst / "images" / dst_split
        out_labels = dst / "labels" / dst_split
        out_images.mkdir(parents=True, exist_ok=True)
        out_labels.mkdir(parents=True, exist_ok=True)
        n = 0
        for img_path in src_images.iterdir():
            if not img_path.is_file():
                continue
            shutil.copy(img_path, out_images / img_path.name)
            n += 1
        for lbl_path in src_labels.glob("*.txt"):
            kept_lines = []
            for line in lbl_path.read_text().splitlines():
                parts = line.split()
                if not parts:
                    continue
                try:
                    cls = int(parts[0])
                except ValueError:
                    continue
                if cls == GLOVE_SRC_ID:
                    kept_lines.append("0 " + " ".join(parts[1:]))
            (out_labels / lbl_path.name).write_text("\n".join(kept_lines))
        counts[dst_split] = n
        print(f"  {src_split:5} -> {dst_split:5}  images: {n}")
    return counts


def write_data_yaml(dst):
    yaml_text = (
        f"path: {dst.resolve()}\n"
        "train: images/train\n"
        "val: images/val\n"
        "test: images/test\n"
        "\n"
        "nc: 1\n"
        "names: ['glove']\n"
    )
    (dst / "data.yaml").write_text(yaml_text)
    print(f"[4/4] Wrote {dst / 'data.yaml'}")


def main():
    raw, dst, _ = resolve_paths()
    if dst.exists():
        print(f"removing existing {dst}")
        shutil.rmtree(dst)
    try:
        zip_path = kaggle_download(raw.parent)
    except FileNotFoundError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as e:
        print(f"ERROR: kaggle CLI failed (exit {e.returncode})", file=sys.stderr)
        return 1
    unzip(zip_path, raw)
    counts = filter_and_remap(raw, dst)
    write_data_yaml(dst)
    total = sum(counts.values())
    print(f"\nDone. {total} glove-labeled images across {len(counts)} splits.")
    print(f"Dataset: {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main())