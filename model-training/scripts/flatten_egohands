"""
Convert the Roboflow EgoHands "specific" 4-class dataset into a single-class
("hand") dataset in the standard YOLOv8 layout.
 
INPUT layout (what Roboflow gave us):
    egohands_yolo_raw/
      train/images/*.jpg + train/labels/*.txt
      valid/images/*.jpg + valid/labels/*.txt
      test/images/*.jpg  + test/labels/*.txt
      data.yaml  (nc: 4, names: myleft/myright/yourleft/yourright)
 
OUTPUT layout (what we actually want):
    egohands_yolo/
      images/train/*.jpg + labels/train/*.txt
      images/val/*.jpg   + labels/val/*.txt
      _test_unused/...                           (kept aside)
      data.yaml  (nc: 1, names: ['hand'])
 
What changes in the label files:
    Every line starts with a class id (0, 1, 2, or 3 in the Roboflow file).
    We rewrite that first number to 0 so everything becomes class "hand".
    The bounding box coordinates are untouched.
 
Usage:
    python scripts/flatten_egohands.py \
        --src datasets/egohands_yolo_raw \
        --dst datasets/egohands_yolo
"""
 
import argparse
import shutil
from pathlib import Path
 
 
def rewrite_label_file(src_path, dst_path):
    """Read a YOLO label file and write a version where every class id is 0."""
    new_lines = []
    for line in src_path.read_text().strip().splitlines():
        parts = line.strip().split()
        if len(parts) < 5:
            # Defensive: skip lines that don't look like a YOLO box.
            continue
        parts[0] = "0"  # force class id to 0 regardless of original
        new_lines.append(" ".join(parts))
    dst_path.write_text("\n".join(new_lines) + ("\n" if new_lines else ""))
 
 
def copy_split(src_root, dst_root, src_split, dst_split):
    """
    Copy one split, reshaping the directory layout and flattening labels.
    src_split: 'train' / 'valid' / 'test'  (Roboflow naming)
    dst_split: 'train' / 'val'  / '_test_unused'  (our naming)
    """
    src_images = src_root / src_split / "images"
    src_labels = src_root / src_split / "labels"
    dst_images = dst_root / "images" / dst_split if dst_split != "_test_unused" \
                 else dst_root / "_test_unused" / "images"
    dst_labels = dst_root / "labels" / dst_split if dst_split != "_test_unused" \
                 else dst_root / "_test_unused" / "labels"
 
    dst_images.mkdir(parents=True, exist_ok=True)
    dst_labels.mkdir(parents=True, exist_ok=True)
 
    n_images = 0
    n_labels = 0
    for img in src_images.iterdir():
        if img.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
            continue
        shutil.copyfile(img, dst_images / img.name)
        n_images += 1
 
        lbl = src_labels / f"{img.stem}.txt"
        if lbl.exists():
            rewrite_label_file(lbl, dst_labels / lbl.name)
            n_labels += 1
        else:
            # No label file means background image — write an empty one so YOLO
            # knows the image exists but has no objects.
            (dst_labels / f"{img.stem}.txt").touch()
 
    return n_images, n_labels
 
 
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", required=True,
                        help="Roboflow raw dataset root (has train/, valid/, test/)")
    parser.add_argument("--dst", required=True,
                        help="Output dataset root (standard YOLOv8 layout)")
    args = parser.parse_args()
 
    src = Path(args.src)
    dst = Path(args.dst)
 
    splits = [
        ("train", "train"),
        ("valid", "val"),
        ("test",  "_test_unused"),
    ]
 
    print(f"Flattening 4-class EgoHands -> single-class 'hand'")
    print(f"  src: {src}")
    print(f"  dst: {dst}\n")
 
    for src_split, dst_split in splits:
        if not (src / src_split).exists():
            print(f"  skip {src_split} (not present)")
            continue
        n_i, n_l = copy_split(src, dst, src_split, dst_split)
        print(f"  {src_split:5} -> {dst_split:14}  images: {n_i}  labels: {n_l}")
 
    (dst / "data.yaml").write_text(
        f"path: {dst.resolve()}\n"
        f"train: images/train\n"
        f"val: images/val\n"
        f"nc: 1\n"
        f"names: ['hand']\n"
    )
    print(f"\n  wrote {dst / 'data.yaml'}")
    print("Done.")
 
 
if __name__ == "__main__":
    main()