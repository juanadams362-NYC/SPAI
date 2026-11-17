"""Unit tests for detection post-processing (no model weights needed)."""
from app.inference.detector import Detector, boxes_conflict, resolve_overlaps
from app.inference.tray_detector import TrayDetector


def det(name, conf, box):
    return {"class_id": 0 if name == "glove" else 1, "class_name": name, "confidence": conf, "box": box}


def names(dets):
    return sorted((d["class_name"], d["confidence"]) for d in dets)


def test_duplicate_hand_label_on_gloved_hand_is_removed():
    # Real model output on a gloved hand: glove 0.73 and hand 0.61 on the same spot.
    out = resolve_overlaps([det("glove", 0.73, [12, 101, 178, 199]), det("hand", 0.61, [16, 121, 187, 199])])
    assert names(out) == [("glove", 0.73)]


def test_ghost_glove_on_bare_hand_is_removed():
    # Real model output on a bare hand: hand 0.80 plus a faint glove 0.28 ghost.
    out = resolve_overlaps([det("hand", 0.80, [135, 23, 224, 115]), det("glove", 0.28, [135, 19, 224, 120])])
    assert names(out) == [("hand", 0.80)]


def test_fragment_inside_a_stronger_box_is_removed():
    # A partial "hand" box sitting inside the gloved-hand box (low IoU, high containment).
    out = resolve_overlaps([det("glove", 0.73, [12, 101, 178, 199]), det("hand", 0.31, [68, 112, 177, 175])])
    assert names(out) == [("glove", 0.73)]


def test_two_different_hands_are_both_kept():
    # A bare hand pulling a glove onto a gloved hand: boxes touch but are different hands.
    out = resolve_overlaps([det("hand", 0.80, [135, 23, 224, 115]), det("glove", 0.73, [12, 101, 178, 199])])
    assert names(out) == [("glove", 0.73), ("hand", 0.80)]


def test_full_real_frame_resolves_to_one_label_per_hand():
    # Every box the current model emits for images-18.jpeg at conf >= 0.15.
    raw = [
        det("hand", 0.80, [135, 23, 224, 115]), det("glove", 0.73, [12, 101, 178, 199]),
        det("hand", 0.61, [16, 121, 187, 199]), det("hand", 0.31, [68, 112, 177, 175]),
        det("glove", 0.28, [135, 19, 224, 120]), det("glove", 0.18, [65, 114, 177, 176]),
    ]
    assert names(resolve_overlaps(raw)) == [("glove", 0.73), ("hand", 0.80)]


def test_non_overlapping_boxes_never_conflict():
    assert not boxes_conflict([0, 0, 10, 10], [20, 20, 30, 30])
    assert resolve_overlaps([]) == []


def test_detector_configuration():
    assert Detector.arbitrate_overlaps is True
    tray = TrayDetector()
    assert tray.agnostic_nms is True and tray.arbitrate_overlaps is False
    assert "overlap_arbitration" in Detector().status()
