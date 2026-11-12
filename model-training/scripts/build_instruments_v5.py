"""
Build the v5 instrument dataset: the ASTRA instruments, re-staged.

Why this exists
---------------
The v4 instrument model was trained on ASTRA as-is: 464 photos from one fixed
overhead camera, of one tray, on one sheet of blue paper, with the instruments
lying mostly upright. It scored 92% mAP on ASTRA's own validation split and
then fell apart on the headset, naming nearly everything as one class. It had
learned that one scene, not the instruments.

The fix is to break the link between the instruments and their scene. ASTRA's
labels are oriented boxes, which lets us cut every instrument out cleanly.
This script cuts them out and composites them into new images where
everything that was constant in ASTRA now varies:

  - rotation: any angle, not just upright
  - scale: from small-in-frame to filling it
  - perspective: tilted toward or away from the camera
  - background: real photos plus procedural colour/texture/clutter
  - lighting: brightness, contrast, colour temperature, blur, sensor noise
  - occlusion: glove- and skin-coloured shapes laid over the handle, the way
    a hand covers part of an instrument that is being held up

The original photos are kept in the mix so the model still handles a real
tray, and ASTRA's own split is respected: cutouts from the test images are
only ever used to build test images, so the "handheld" test set measures
generalisation, not memory.

Usage
-----
    python build_instruments_v5.py --astra /path/to/ASTRA-raw-dataset \
        --out /path/to/v5_dataset --backgrounds dir1 dir2 ...

ASTRA Surgical Instruments is CC BY 4.0:
https://universe.roboflow.com/astra-juyrg/astra-surgical-instruments-erspj
"""
from __future__ import annotations

import argparse
import glob
import math
import os
import random
import shutil

import cv2
import numpy as np

NAMES = [
    "Adson Dressing Forceps",
    "Babcock Tissue Forceps",
    "Halsted Mosquito Forceps",
    "Mayo Hegar Needle Holder",
    "Operating Scissors",
    "Scalpel Handle 3",
]

W, H = 640, 480

# Nitrile blue / purple / white / green gloves and a range of skin tones (BGR).
HAND_COLOURS = [
    (190, 110, 40), (200, 130, 60), (170, 90, 110), (235, 235, 235),
    (150, 170, 90), (120, 160, 215), (95, 130, 190), (70, 100, 160), (50, 70, 120),
]


# --------------------------------------------------------------------------
# Cutting instruments out of ASTRA
# --------------------------------------------------------------------------

def read_obb_labels(path: str) -> list[tuple[int, np.ndarray]]:
    """YOLO-OBB label file -> [(class_id, 4x2 corner array in 0..1)]."""
    out = []
    if not os.path.exists(path):
        return out
    for line in open(path):
        parts = line.split()
        if len(parts) != 9:
            continue
        out.append((int(parts[0]), np.array(parts[1:], dtype=np.float32).reshape(4, 2)))
    return out


def cut_out(image: np.ndarray, corners: np.ndarray, pad: float = 0.12) -> np.ndarray | None:
    """Cut one instrument out as an upright BGRA image with a soft alpha mask.

    The oriented box is straightened first, then the instrument is separated
    from the paper it lies on by colour: the paper is the dominant colour
    around the edge of the box, and anything far enough from it is instrument.
    """
    h, w = image.shape[:2]
    pts = corners * [w, h]
    rect = cv2.minAreaRect(pts.astype(np.float32))
    (cx, cy), (rw, rh), angle = rect
    if rw < 6 or rh < 6:
        return None
    # Straighten so the long side is vertical.
    if rw > rh:
        angle += 90
        rw, rh = rh, rw
    rw, rh = rw * (1 + pad * 2.2), rh * (1 + pad)
    M = cv2.getRotationMatrix2D((cx, cy), angle, 1.0)
    M[0, 2] += rw / 2 - cx
    M[1, 2] += rh / 2 - cy
    crop = cv2.warpAffine(image, M, (int(round(rw)), int(round(rh))),
                          flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    ch, cw = crop.shape[:2]
    if ch < 12 or cw < 6:
        return None

    lab = cv2.cvtColor(crop, cv2.COLOR_BGR2LAB).astype(np.float32)
    border = max(2, int(min(ch, cw) * 0.06))
    edge = np.concatenate([
        lab[:border].reshape(-1, 3), lab[-border:].reshape(-1, 3),
        lab[:, :border].reshape(-1, 3), lab[:, -border:].reshape(-1, 3),
    ])
    paper = np.median(edge, axis=0)
    spread = np.percentile(np.linalg.norm(edge - paper, axis=1), 90)
    dist = np.linalg.norm(lab - paper, axis=2)
    mask = (dist > max(9.0, spread * 1.6)).astype(np.uint8) * 255

    # Polished steel reflects the paper, leaving holes; close them, then keep
    # only the pieces big enough to be instrument rather than paper texture.
    k = max(3, int(round(cw * 0.06)) | 1)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k)))
    n, labels, stats, _ = cv2.connectedComponentsWithStats(mask)
    keep = np.zeros_like(mask)
    min_area = 0.004 * ch * cw
    for i in range(1, n):
        if stats[i, cv2.CC_STAT_AREA] >= min_area:
            keep[labels == i] = 255
    if keep.mean() / 255 < 0.03 or keep.mean() / 255 > 0.85:
        return None  # segmentation failed; skip rather than paste a bad cutout
    keep = cv2.dilate(keep, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)))
    alpha = cv2.GaussianBlur(keep, (0, 0), 0.8)

    # Trim to the instrument so the label box is tight.
    ys, xs = np.where(alpha > 40)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    return np.dstack([crop[y0:y1, x0:x1], alpha[y0:y1, x0:x1]])


def harvest(astra: str, split: str) -> list[tuple[int, np.ndarray]]:
    cutouts = []
    for img_path in sorted(glob.glob(f"{astra}/{split}/images/*")):
        stem = os.path.splitext(os.path.basename(img_path))[0]
        labels = read_obb_labels(f"{astra}/{split}/labels/{stem}.txt")
        if not labels:
            continue
        image = cv2.imread(img_path)
        for cls, corners in labels:
            cut = cut_out(image, corners)
            if cut is not None:
                cutouts.append((cls, cut))
    return cutouts


# --------------------------------------------------------------------------
# Backgrounds
# --------------------------------------------------------------------------

def procedural_background(rng: random.Random) -> np.ndarray:
    """A background with no instruments in it: gradients, texture, clutter."""
    base = np.array([rng.randint(20, 235) for _ in range(3)], dtype=np.float32)
    if rng.random() < 0.5:  # desaturate: benches, drapes and walls are mostly neutral
        base = base * 0.35 + base.mean() * 0.65
    img = np.ones((H, W, 3), np.float32) * base
    # Lighting gradient.
    gx, gy = np.meshgrid(np.linspace(-1, 1, W), np.linspace(-1, 1, H))
    a = rng.uniform(0, 2 * math.pi)
    img += (gx * math.cos(a) + gy * math.sin(a))[..., None] * rng.uniform(10, 60)
    # Soft clutter: blurred blobs and straight edges (tray rims, drapes, sleeves).
    for _ in range(rng.randint(0, 7)):
        colour = [rng.randint(0, 255) for _ in range(3)]
        if rng.random() < 0.5:
            cv2.ellipse(img, (rng.randint(0, W), rng.randint(0, H)),
                        (rng.randint(20, 260), rng.randint(20, 200)), rng.uniform(0, 180), 0, 360, colour, -1)
        else:
            p = np.array([[rng.randint(-50, W + 50), rng.randint(-50, H + 50)] for _ in range(4)])
            cv2.fillConvexPoly(img, cv2.convexHull(p), colour)
    img = cv2.GaussianBlur(img, (0, 0), rng.uniform(2, 14))
    # Fabric / paper grain.
    grain = np.random.default_rng(rng.randint(0, 1 << 30)).normal(0, rng.uniform(2, 9), (H // 2, W // 2, 1))
    img += cv2.resize(grain.astype(np.float32), (W, H))[..., None]
    return np.clip(img, 0, 255).astype(np.uint8)


def photo_background(path: str, rng: random.Random) -> np.ndarray:
    img = cv2.imread(path)
    if img is None:
        return procedural_background(rng)
    h, w = img.shape[:2]
    # Random crop at the output aspect ratio, random flip.
    scale = rng.uniform(0.45, 1.0)
    cw = int(min(w, h * W / H) * scale)
    ch = int(cw * H / W)
    x, y = rng.randint(0, w - cw), rng.randint(0, h - ch)
    img = cv2.resize(img[y:y + ch, x:x + cw], (W, H), interpolation=cv2.INTER_AREA)
    if rng.random() < 0.5:
        img = img[:, ::-1]
    return np.ascontiguousarray(img)


# --------------------------------------------------------------------------
# Compositing
# --------------------------------------------------------------------------

def relight(cut: np.ndarray, rng: random.Random) -> np.ndarray:
    """Vary how the steel looks: exposure, contrast, colour cast."""
    bgr = cut[..., :3].astype(np.float32)
    gain = rng.uniform(0.6, 1.35)
    bias = rng.uniform(-25, 25)
    cast = np.array([rng.uniform(0.9, 1.1) for _ in range(3)], np.float32)
    bgr = (bgr - 128) * rng.uniform(0.8, 1.3) + 128
    bgr = np.clip(bgr * gain * cast + bias, 0, 255)
    return np.dstack([bgr.astype(np.uint8), cut[..., 3]])


def transform(cut: np.ndarray, rng: random.Random, target_long: float) -> tuple[np.ndarray, np.ndarray]:
    """Rotate, scale and tilt a cutout. Returns (BGRA patch, its 4 corner points)."""
    h, w = cut.shape[:2]
    s = target_long / max(h, w)
    angle = rng.uniform(0, 360)
    # Foreshortening: squash along one axis as if tilted toward the camera.
    sx, sy = s * rng.uniform(0.75, 1.0), s * rng.uniform(0.6, 1.0)
    if rng.random() < 0.5:
        sx = -sx  # mirror
    c, si = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    A = np.array([[c * sx, -si * sy], [si * sx, c * sy]], np.float32)
    corners = np.array([[0, 0], [w, 0], [w, h], [0, h]], np.float32) - [w / 2, h / 2]
    out = corners @ A.T
    # Mild perspective on top of the affine.
    out += np.array([[rng.uniform(-1, 1) for _ in range(2)] for _ in range(4)], np.float32) * target_long * 0.035
    mn = out.min(axis=0)
    out -= mn
    size = np.ceil(out.max(axis=0)).astype(int) + 1
    P = cv2.getPerspectiveTransform((corners + [w / 2, h / 2]).astype(np.float32), out.astype(np.float32))
    patch = cv2.warpPerspective(cut, P, (int(size[0]), int(size[1])),
                                flags=cv2.INTER_AREA if s < 1 else cv2.INTER_LINEAR,
                                borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0))
    return patch, out


def paste(canvas: np.ndarray, patch: np.ndarray, x: int, y: int, shadow: bool, rng: random.Random):
    """Alpha-blend a patch onto the canvas. Returns the visible box, or None."""
    ph, pw = patch.shape[:2]
    x0, y0, x1, y1 = max(x, 0), max(y, 0), min(x + pw, W), min(y + ph, H)
    if x1 - x0 < 4 or y1 - y0 < 4:
        return None
    sub = patch[y0 - y:y1 - y, x0 - x:x1 - x]
    alpha = sub[..., 3:4].astype(np.float32) / 255
    if shadow:
        # Soft contact shadow, offset a little, so it sits on the surface.
        dx, dy = rng.randint(-6, 6), rng.randint(2, 8)
        sh = cv2.GaussianBlur(sub[..., 3], (0, 0), rng.uniform(3, 7)).astype(np.float32) / 255 * rng.uniform(0.2, 0.5)
        sx0, sy0 = min(max(x0 + dx, 0), W), min(max(y0 + dy, 0), H)
        sx1, sy1 = min(sx0 + sh.shape[1], W), min(sy0 + sh.shape[0], H)
        region = canvas[sy0:sy1, sx0:sx1].astype(np.float32)
        region *= 1 - sh[:sy1 - sy0, :sx1 - sx0, None]
        canvas[sy0:sy1, sx0:sx1] = region.astype(np.uint8)
    region = canvas[y0:y1, x0:x1].astype(np.float32)
    canvas[y0:y1, x0:x1] = (region * (1 - alpha) + sub[..., :3].astype(np.float32) * alpha).astype(np.uint8)
    ys, xs = np.where(sub[..., 3] > 60)
    if len(xs) < 20:
        return None
    return [x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1]


def draw_hand(canvas: np.ndarray, box: list[int], rng: random.Random) -> None:
    """Lay a hand-like shape over part of an instrument.

    Not a realistic hand — a palm blob with a few finger-width bars across the
    instrument, in glove and skin colours. What matters is that the model sees
    instruments that are partly covered, with their handles broken up, since
    that is what a held instrument looks like.
    """
    x0, y0, x1, y1 = box
    bw, bh = x1 - x0, y1 - y0
    colour = np.array(rng.choice(HAND_COLOURS), np.float32)
    colour = np.clip(colour * rng.uniform(0.7, 1.15), 0, 255)
    layer = np.zeros((H, W), np.uint8)

    # Grip somewhere along the instrument, biased toward one end (the handle).
    t = rng.choice([rng.uniform(0.0, 0.35), rng.uniform(0.65, 1.0)])
    gx, gy = x0 + bw * rng.uniform(0.3, 0.7), y0 + bh * t
    # Sized like a real grip: covers a quarter to a third of the instrument,
    # leaving the working end — the part that tells instruments apart — visible.
    size = max(bw, bh) * rng.uniform(0.13, 0.24)
    angle = rng.uniform(0, 180)
    cv2.ellipse(layer, (int(gx), int(gy)), (int(size), int(size * rng.uniform(0.55, 0.9))), angle, 0, 360, 255, -1)
    finger_w = max(6, int(size * rng.uniform(0.28, 0.4)))
    for _ in range(rng.randint(1, 4)):
        fa = math.radians(angle + rng.uniform(-50, 50))
        length = size * rng.uniform(0.9, 1.6)
        off = rng.uniform(-0.8, 0.8) * size
        sx, sy = gx - math.sin(fa) * off, gy + math.cos(fa) * off
        cv2.line(layer, (int(sx), int(sy)), (int(sx + math.cos(fa) * length), int(sy + math.sin(fa) * length)),
                 255, finger_w, cv2.LINE_AA)
    layer = cv2.GaussianBlur(layer, (0, 0), 1.5)
    a = (layer.astype(np.float32) / 255)[..., None]

    # Shading so it isn't a flat sticker.
    shade = cv2.GaussianBlur(np.random.default_rng(rng.randint(0, 1 << 30)).normal(0, 1, (H // 8, W // 8)).astype(np.float32), (0, 0), 2)
    shade = cv2.resize(shade, (W, H))[..., None] * 22
    hand = np.clip(colour + shade, 0, 255)
    canvas[:] = (canvas.astype(np.float32) * (1 - a) + hand * a).astype(np.uint8)


def camera_effects(img: np.ndarray, rng: random.Random) -> np.ndarray:
    """What a headset or phone camera does to the scene."""
    out = img.astype(np.float32)
    out = (out - 128) * rng.uniform(0.75, 1.25) + 128 + rng.uniform(-30, 30)
    out *= np.array([rng.uniform(0.9, 1.1) for _ in range(3)], np.float32)
    out = np.clip(out, 0, 255).astype(np.uint8)
    r = rng.random()
    if r < 0.25:
        out = cv2.GaussianBlur(out, (0, 0), rng.uniform(0.6, 2.0))
    elif r < 0.45:  # motion blur — a hand is rarely still
        k = rng.choice([5, 7, 9, 11])
        kernel = np.zeros((k, k), np.float32)
        kernel[k // 2, :] = 1 / k
        M = cv2.getRotationMatrix2D((k / 2 - 0.5, k / 2 - 0.5), rng.uniform(0, 180), 1)
        kernel = cv2.warpAffine(kernel, M, (k, k))
        out = cv2.filter2D(out, -1, kernel / max(kernel.sum(), 1e-6))
    if rng.random() < 0.5:
        noise = np.random.default_rng(rng.randint(0, 1 << 30)).normal(0, rng.uniform(2, 8), out.shape)
        out = np.clip(out.astype(np.float32) + noise, 0, 255).astype(np.uint8)
    if rng.random() < 0.3:  # JPEG artefacts from a compressed stream
        _, enc = cv2.imencode(".jpg", out, [cv2.IMWRITE_JPEG_QUALITY, rng.randint(35, 75)])
        out = cv2.imdecode(enc, cv2.IMREAD_COLOR)
    return out


def compose(cutouts, backgrounds, rng: random.Random, handheld: bool):
    """One synthetic image and its YOLO labels."""
    if backgrounds and rng.random() < 0.5:
        canvas = photo_background(rng.choice(backgrounds), rng)
    else:
        canvas = procedural_background(rng)

    # Handheld shots are one instrument, large in frame. Bench shots are several, smaller.
    count = 1 if handheld and rng.random() < 0.8 else rng.randint(1, 4)
    labels, boxes = [], []
    for _ in range(count):
        cls, cut = rng.choice(cutouts)
        long_side = rng.uniform(0.35, 0.95) * H if handheld else rng.uniform(0.16, 0.6) * H
        patch, _ = transform(relight(cut, rng), rng, long_side)
        ph, pw = patch.shape[:2]
        x = rng.randint(-pw // 6, max(W - pw + pw // 6, 1))
        y = rng.randint(-ph // 6, max(H - ph + ph // 6, 1))
        box = paste(canvas, patch, x, y, shadow=not handheld and rng.random() < 0.7, rng=rng)
        if box is None:
            continue
        if (box[2] - box[0]) * (box[3] - box[1]) < 0.35 * pw * ph * 0.3:
            continue  # mostly off-frame
        boxes.append(box)
        labels.append(cls)

    hold = 0.85 if handheld else 0.15
    for box in boxes:
        if rng.random() < hold:
            draw_hand(canvas, box, rng)

    canvas = camera_effects(canvas, rng)
    lines = []
    for cls, (x0, y0, x1, y1) in zip(labels, boxes):
        lines.append(f"{cls} {(x0 + x1) / 2 / W:.6f} {(y0 + y1) / 2 / H:.6f} {(x1 - x0) / W:.6f} {(y1 - y0) / H:.6f}")
    return canvas, lines


# --------------------------------------------------------------------------
# Dataset assembly
# --------------------------------------------------------------------------

def copy_originals(astra: str, split: str, out: str, dest: str) -> int:
    """Original ASTRA photos, with oriented labels converted to plain boxes."""
    n = 0
    for img_path in sorted(glob.glob(f"{astra}/{split}/images/*")):
        stem = os.path.splitext(os.path.basename(img_path))[0]
        lines = []
        for cls, corners in read_obb_labels(f"{astra}/{split}/labels/{stem}.txt"):
            x0, y0 = corners.min(axis=0)
            x1, y1 = corners.max(axis=0)
            lines.append(f"{cls} {(x0 + x1) / 2:.6f} {(y0 + y1) / 2:.6f} {x1 - x0:.6f} {y1 - y0:.6f}")
        shutil.copy(img_path, f"{out}/{dest}/images/astra_{stem}.jpg")
        open(f"{out}/{dest}/labels/astra_{stem}.txt", "w").write("\n".join(lines))
        n += 1
    return n


def synthesize(cutouts, backgrounds, out, dest, prefix, count, handheld_share, seed) -> None:
    rng = random.Random(seed)
    for i in range(count):
        handheld = rng.random() < handheld_share
        img, lines = compose(cutouts, backgrounds, rng, handheld)
        cv2.imwrite(f"{out}/{dest}/images/{prefix}_{i:05d}.jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 90])
        open(f"{out}/{dest}/labels/{prefix}_{i:05d}.txt", "w").write("\n".join(lines))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--astra", required=True, help="ASTRA dataset root (train/ valid/ test/ with OBB labels)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--backgrounds", nargs="*", default=[], help="folders of instrument-free photos")
    ap.add_argument("--train", type=int, default=2400, help="synthetic training images")
    ap.add_argument("--val", type=int, default=300)
    ap.add_argument("--test", type=int, default=400)
    ap.add_argument("--negatives", type=int, default=200, help="instrument-free training images")
    ap.add_argument("--seed", type=int, default=5)
    args = ap.parse_args()

    backgrounds = []
    for folder in args.backgrounds:
        for ext in ("jpg", "jpeg", "png"):
            backgrounds += glob.glob(f"{folder}/**/*.{ext}", recursive=True)
    backgrounds.sort()
    rng = random.Random(args.seed)
    rng.shuffle(backgrounds)
    # Backgrounds are split too, so test scenes are never seen in training.
    cut = int(len(backgrounds) * 0.8)
    bg_train, bg_test = backgrounds[:cut], backgrounds[cut:]

    if os.path.exists(args.out):
        shutil.rmtree(args.out)
    for split in ("train", "val", "test_astra", "test_handheld"):
        os.makedirs(f"{args.out}/{split}/images")
        os.makedirs(f"{args.out}/{split}/labels")

    cuts = {s: harvest(args.astra, s) for s in ("train", "valid", "test")}
    for s, c in cuts.items():
        print(f"cutouts from ASTRA {s}: {len(c)}")

    n = copy_originals(args.astra, "train", args.out, "train")
    synthesize(cuts["train"], bg_train, args.out, "train", "syn", args.train, 0.6, args.seed + 1)
    # Negatives: scenes and bare hands with no instrument, so "nothing" is a valid answer.
    for i in range(args.negatives):
        bg = photo_background(rng.choice(bg_train), rng) if bg_train and rng.random() < 0.6 else procedural_background(rng)
        if rng.random() < 0.5:
            draw_hand(bg, [rng.randint(0, W // 2), rng.randint(0, H // 2), rng.randint(W // 2, W), rng.randint(H // 2, H)], rng)
        cv2.imwrite(f"{args.out}/train/images/neg_{i:05d}.jpg", camera_effects(bg, rng))
        open(f"{args.out}/train/labels/neg_{i:05d}.txt", "w").write("")
    print(f"train: {n} ASTRA photos + {args.train} synthetic + {args.negatives} negatives")

    n = copy_originals(args.astra, "valid", args.out, "val")
    synthesize(cuts["valid"], bg_test, args.out, "val", "syn", args.val, 0.6, args.seed + 2)
    print(f"val: {n} ASTRA photos + {args.val} synthetic")

    n = copy_originals(args.astra, "test", args.out, "test_astra")
    print(f"test_astra: {n} untouched ASTRA photos (the old model's home turf)")
    synthesize(cuts["test"], bg_test, args.out, "test_handheld", "held", args.test, 1.0, args.seed + 3)
    print(f"test_handheld: {args.test} handheld-style images from held-out instruments and backgrounds")

    names = "\n".join(f"  {i}: {n}" for i, n in enumerate(NAMES))
    for name, val in (("data.yaml", "val/images"), ("data_test_astra.yaml", "test_astra/images"),
                      ("data_test_handheld.yaml", "test_handheld/images")):
        open(f"{args.out}/{name}", "w").write(
            f"path: {os.path.abspath(args.out)}\ntrain: train/images\nval: {val}\nnames:\n{names}\n")


if __name__ == "__main__":
    main()
