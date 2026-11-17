"""
Instrument knowledge base.

The instrument model knows six instruments by name. This module turns a raw
model label into something a trainee can actually use: a clean display name,
what the instrument is for, how to recognise it, and what to check at the
inspection bench.

It also holds the "which instrument is the user holding up?" rule, so the
/analyze and /detect-tray routes — and the Ask SPAI prompt — all agree on
the answer.

Pure data and pure functions: no model, no framework. Fully unit-testable.
The visionOS app carries a matching copy (InstrumentCatalog.swift) so it can
still name an instrument when it falls back to on-device detection.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, asdict

# Label used when something instrument-shaped is detected but we are not
# confident which instrument it is. Also what older builds of this backend
# reported for every instrument, so the app already understands it.
GENERIC_LABEL = "instrument"

# Below this confidence we say "an instrument" instead of guessing a name.
# A wrong name is worse than no name for someone learning the set. Tunable at
# runtime with PATCH /settings {"identify_threshold": ...}.
DEFAULT_IDENTIFY_THRESHOLD = 0.60


@dataclass(frozen=True)
class InstrumentInfo:
    """Everything SPAI can say about one instrument."""

    key: str            # stable id, e.g. "mayo_hegar_needle_holder"
    name: str           # display name, e.g. "Mayo-Hegar Needle Holder"
    category: str       # family, e.g. "Needle holder"
    summary: str        # one line: what it is for
    spoken: str         # short sentence read aloud when identified
    identify_by: str    # how to tell it apart from look-alikes
    inspect: tuple[str, ...]   # inspection-bench checkpoints
    handling: str       # decontamination / assembly handling note

    def as_dict(self) -> dict:
        data = asdict(self)
        data["inspect"] = list(self.inspect)
        return data


_CATALOG: tuple[InstrumentInfo, ...] = (
    InstrumentInfo(
        key="adson_dressing_forceps",
        name="Adson Dressing Forceps",
        category="Thumb forceps",
        summary="Fine-tipped thumb forceps for handling dressings and delicate tissue.",
        spoken="Adson dressing forceps. Fine-tipped thumb forceps for dressings and delicate tissue.",
        identify_by="Tweezer-style with a wide flat grip that narrows to fine, serrated tips. "
                    "No teeth and no ratchet.",
        inspect=(
            "Tips meet evenly along their length and do not cross",
            "Serrations are clean with no trapped soil",
            "Spring tension returns the tips open",
        ),
        handling="Protect the fine tips — never stack heavy instruments on top.",
    ),
    InstrumentInfo(
        key="babcock_tissue_forceps",
        name="Babcock Tissue Forceps",
        category="Grasping forceps",
        summary="Ratcheted forceps with rounded, open jaws for holding delicate tissue without crushing it.",
        spoken="Babcock tissue forceps. Rounded open jaws that hold delicate tissue without crushing it.",
        identify_by="Ring handles and a ratchet, with broad, flared, window-like (fenestrated) "
                    "jaw tips that have no teeth.",
        inspect=(
            "Jaws meet evenly at the tips",
            "Box lock is clean and moves smoothly",
            "Ratchet holds on every tooth and releases cleanly",
        ),
        handling="Clean and sterilize unlocked and open so the box lock is exposed.",
    ),
    InstrumentInfo(
        key="halsted_mosquito_forceps",
        name="Halsted Mosquito Forceps",
        category="Hemostat",
        summary="Small, fine hemostat for clamping small blood vessels.",
        spoken="Halsted mosquito forceps. A small, fine hemostat for clamping small vessels.",
        identify_by="The smallest ratcheted clamp in the set: ring handles with short, slim jaws "
                    "serrated along their full length.",
        inspect=(
            "Tips align and close fully with no gap",
            "Ratchet holds on the first tooth",
            "Box lock is free of soil, cracks, and rust",
        ),
        handling="Open the ratchet before cleaning; string on a stringer with hinges open for assembly.",
    ),
    InstrumentInfo(
        key="mayo_hegar_needle_holder",
        name="Mayo-Hegar Needle Holder",
        category="Needle holder",
        summary="Ratcheted needle holder with short, heavy jaws for driving suture needles.",
        spoken="Mayo-Hegar needle holder. Short, heavy jaws that grip a suture needle.",
        identify_by="Looks like a sturdy hemostat, but the jaws are shorter and thicker with a "
                    "cross-hatched grip. Gold ring handles mean tungsten carbide jaw inserts.",
        inspect=(
            "Jaw surface is not worn smooth — a needle should not rotate when clamped",
            "No light shows between closed jaws",
            "Ratchet holds and box lock moves smoothly",
        ),
        handling="Check the jaw inserts for cracks or lifting before it goes in the tray.",
    ),
    InstrumentInfo(
        key="operating_scissors",
        name="Operating Scissors",
        category="Scissors",
        summary="General-purpose scissors for cutting suture, dressings, and drapes.",
        spoken="Operating scissors. General-purpose scissors for suture and dressings.",
        identify_by="Straight or curved blades with ring handles and no ratchet. "
                    "Tips may be sharp, blunt, or one of each.",
        inspect=(
            "Blades are free of nicks, burrs, and cracks",
            "Blades cut cleanly to the tip on test material",
            "Screw joint is tight and the action is smooth",
        ),
        handling="Keep blades open during cleaning and protect the tips in the tray.",
    ),
    InstrumentInfo(
        key="scalpel_handle_3",
        name="Scalpel Handle No. 3",
        category="Scalpel handle",
        summary="Reusable knife handle that holds small blades — numbers 10, 11, 12, and 15.",
        spoken="Number 3 scalpel handle. It holds blades 10, 11, 12, and 15.",
        identify_by="A flat, slim metal handle with a narrow grooved tip where the blade "
                    "slides on. No moving parts.",
        inspect=(
            "No blade is still attached",
            "Blade slot is clean, straight, and not bent or worn",
            "Grip grooves are free of soil",
        ),
        handling="Blades must be removed with a blade remover before decontamination — never by hand.",
    ),
)


def _normalize(label: str) -> str:
    """Collapse a model label to a lookup key: lowercase, digits and letters only."""
    return re.sub(r"[^a-z0-9]+", "_", label.strip().lower()).strip("_")


_BY_KEY: dict[str, InstrumentInfo] = {info.key: info for info in _CATALOG}

# Alternate spellings the model or a relabelled dataset might produce.
_ALIASES: dict[str, str] = {
    "adson_forceps": "adson_dressing_forceps",
    "babcock_forceps": "babcock_tissue_forceps",
    "mosquito_forceps": "halsted_mosquito_forceps",
    "halsted_mosquito": "halsted_mosquito_forceps",
    "needle_holder": "mayo_hegar_needle_holder",
    "mayo_hegar": "mayo_hegar_needle_holder",
    "scissors": "operating_scissors",
    "scalpel_handle": "scalpel_handle_3",
    "scalpel_handle_no_3": "scalpel_handle_3",
    "scalpel": "scalpel_handle_3",
}


def all_instruments() -> list[InstrumentInfo]:
    """Every instrument SPAI can describe, in a stable order."""
    return list(_CATALOG)


def key_for(label: str) -> str:
    """The catalog key a model label maps to (or its normalized form if unknown)."""
    key = _normalize(label)
    return _ALIASES.get(key, key)


def lookup(label: str) -> InstrumentInfo | None:
    """Find the catalog entry for a model label or key. None if we don't know it."""
    return _BY_KEY.get(key_for(label))


def display_name(label: str) -> str:
    """Clean display name for a model label, falling back to the label itself."""
    info = lookup(label)
    if info:
        return info.name
    return label.strip() or GENERIC_LABEL


def is_generic(label: str) -> bool:
    return _normalize(label) in ("", GENERIC_LABEL, "instruments", "tool", "tools")


# --- "Which instrument is being held up?" ------------------------------------

# How far a hand/glove box is grown before testing overlap with an instrument.
# Fingers wrap the handle, so the boxes usually touch rather than fully overlap.
_HAND_REACH = 0.15


def _expanded(box: list[int], factor: float) -> tuple[float, float, float, float]:
    x1, y1, x2, y2 = box
    dx = (x2 - x1) * factor
    dy = (y2 - y1) * factor
    return (x1 - dx, y1 - dy, x2 + dx, y2 + dy)


def _overlaps(a: tuple[float, float, float, float], b: list[int]) -> bool:
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def _area(box: list[int]) -> int:
    return max(box[2] - box[0], 0) * max(box[3] - box[1], 0)


def mark_held(instruments: list[dict], hands: list[dict]) -> None:
    """Flag each instrument detection with whether a hand or glove is on it."""
    reach = [_expanded(h["box"], _HAND_REACH) for h in hands if len(h.get("box", [])) == 4]
    for det in instruments:
        box = det.get("box", [])
        det["held"] = len(box) == 4 and any(_overlaps(r, box) for r in reach)


def identify(
    instruments: list[dict],
    threshold: float = DEFAULT_IDENTIFY_THRESHOLD,
) -> dict | None:
    """Pick the one instrument the user is most likely showing us.

    Preference order: an instrument in someone's hand beats one lying on the
    bench; then the more confident detection; then the larger one. Returns
    None when no instrument is in frame.

    The result is honest about uncertainty: below `threshold` it reports a
    generic instrument rather than a name it isn't sure of.
    """
    if not instruments:
        return None

    best = max(
        instruments,
        key=lambda d: (bool(d.get("held")), d.get("confidence", 0.0), _area(d.get("box", [0, 0, 0, 0]))),
    )
    confidence = float(best.get("confidence", 0.0))
    info = lookup(best.get("class_name", ""))
    certain = info is not None and confidence >= threshold

    if not certain or info is None:
        return {
            "key": GENERIC_LABEL,
            "name": "Instrument",
            "certain": False,
            "confidence": round(confidence, 3),
            "held": bool(best.get("held")),
            "box": best.get("box"),
            "spoken": "I can see an instrument, but I'm not sure which one. "
                      "Hold it flat and a little closer.",
            "info": None,
        }

    return {
        "key": info.key,
        "name": info.name,
        "certain": True,
        "confidence": round(confidence, 3),
        "held": bool(best.get("held")),
        "box": best.get("box"),
        "spoken": info.spoken,
        "info": info.as_dict(),
    }


def facts_for_prompt(labels: list[str]) -> str:
    """Reference facts for the named instruments, formatted for the LLM prompt.

    Ask SPAI is only allowed to answer from what we hand it, so this is what
    lets it answer "what am I holding?" without inventing anything.
    """
    seen: list[InstrumentInfo] = []
    for label in labels:
        info = lookup(label)
        if info and info not in seen:
            seen.append(info)
    if not seen:
        return ""
    lines = []
    for info in seen:
        checks = "; ".join(info.inspect)
        lines.append(
            f"- {info.name} ({info.category}): {info.summary} "
            f"Recognise it by: {info.identify_by} "
            f"Inspection checks: {checks}. Handling: {info.handling}"
        )
    return "\n".join(lines)


def mentioned_in(text: str) -> list[str]:
    """Catalog keys for every instrument whose name appears in free text."""
    haystack = _normalize(text)
    found = []
    for info in _CATALOG:
        if _normalize(info.name) in haystack or info.key in haystack:
            found.append(info.key)
    return found
