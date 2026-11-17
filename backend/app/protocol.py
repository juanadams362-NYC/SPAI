"""
The institution's protocol: what SPAI says at each station, what it checks,
which tray count sheets exist, and how runs are scored.

Ships with a standard protocol. An institution can replace any of it from
the instructor dashboard; their version is saved to disk and served to every
headset, so a school teaches its own procedure, in its own words, without a
new app build. Ask SPAI answers from the same text.
"""
from __future__ import annotations

import copy

from app import instruments, scoring

# What the app can verify with the camera before letting a step advance.
CONDITIONS = ("manual", "gloves_on", "instruments_present", "tray_loaded", "count_matches")

MAX_STEPS_PER_STATION = 10
MAX_INSTRUCTION_LENGTH = 400


def _step(instruction: str, condition: str = "manual", why: str = "") -> dict:
    return {"instruction": instruction, "condition": condition, "why": why}


STANDARD_STATIONS = [
    {"key": "decontamination", "title": "Decontamination", "steps": [
        _step("Put on your protective gear: a fluid-resistant mask with eye protection, a gown, and heavy-duty gloves.",
              "gloves_on", "It keeps splashes and germs off you before you touch anything dirty."),
        _step("Keep the instruments wet and take apart any that come apart.",
              "instruments_present", "Dried-on soil is much harder to clean, and hidden surfaces need to be exposed."),
        _step("Scrub gently under the water line with a soft brush. Brush and flush any instrument with a channel inside.",
              "manual", "Scrubbing under water stops soil spraying into the air."),
        _step("Open and unlock any hinged instruments, then load them into the ultrasonic cleaner or washer.",
              "manual", "Open hinges let the machine clean every surface."),
    ]},
    {"key": "inspection", "title": "Inspection", "steps": [
        _step("Make sure your gloves are on and your hands are clean before you handle cleaned instruments.",
              "gloves_on", "From here on, everything needs to stay clean."),
        _step("Look over each instrument under good light and magnification for leftover soil, stains, or rust.",
              "instruments_present", "Anything left on an instrument survives sterilization."),
        _step("Test the moving parts: hinges open and close smoothly, ratchets hold, tips line up.",
              "manual", "An instrument that doesn't work is as much a failure as one that isn't clean."),
        _step("Pull anything that fails. Still dirty goes back to decontamination; broken goes to repair.",
              "manual", "A failed instrument must never reach the tray."),
    ]},
    {"key": "tray_assembly", "title": "Tray Assembly", "steps": [
        _step("Check the count sheet. Make sure you have the right sheet for the right tray.",
              "manual", "The sheet lists exactly what goes in this tray."),
        _step("Lay the instruments in as the sheet shows: hinges open, tips pointing the same way, not overcrowded.",
              "tray_loaded", "This lets steam reach every surface."),
        _step("Count the instruments and match them to the sheet exactly.",
              "count_matches", "A missing or extra instrument delays a surgery."),
        _step("Add the chemical indicator in the spot hardest for steam to reach, then close the tray.",
              "manual", "It confirms the sterilizer reached the whole tray."),
    ]},
    {"key": "packaging", "title": "Packaging", "steps": [
        _step("Pick the right wrap or container for the tray's size and weight.",
              "manual", "The wrong packaging can tear or block steam."),
        _step("Wrap it snugly with no gaps, holes, or thin spots.",
              "manual", "Any opening lets germs back in after sterilizing."),
        _step("Seal it with indicator tape and label it with the contents, date, and your initials.",
              "manual", "Never use clips or staples, which poke holes."),
    ]},
    {"key": "seal_validation", "title": "Seal Validation", "steps": [
        _step("Check the seal all the way around for gaps, wrinkles, or open channels.",
              "manual", "A channel in the seal is a path for germs."),
        _step("Make sure the outside indicator is there and hasn't already changed color.",
              "manual", "A changed indicator means the pack has already been through a cycle."),
        _step("Check that the label is complete and easy to read, then send the tray to be sterilized.",
              "manual", "The label is how the OR knows what it's opening."),
    ]},
]


def standard_protocol() -> dict:
    return {
        "name": "SPAI standard protocol",
        "version": 1,
        "updated_at": None,
        "is_standard": True,
        "stations": copy.deepcopy(STANDARD_STATIONS),
        "count_sheets": [{
            "id": "basic_minor_set",
            "name": "Basic Minor Set",
            "items": [{"key": info.key, "name": info.name, "count": 1} for info in instruments.all_instruments()],
        }],
        "rubric": dict(scoring.DEFAULT_RUBRIC),
    }


class ProtocolError(ValueError):
    """The submitted protocol can't be used; the message says why."""


def validate(candidate: dict) -> dict:
    """Check and normalize a protocol an instructor has edited.

    Strict on purpose: this text is read aloud to students at a sink, so a
    half-saved or malformed protocol must never go live.
    """
    standard = standard_protocol()
    stations_in = candidate.get("stations")
    if not isinstance(stations_in, list):
        raise ProtocolError("A protocol needs a list of stations.")

    by_key = {s.get("key"): s for s in stations_in if isinstance(s, dict)}
    stations = []
    for base in standard["stations"]:
        given = by_key.get(base["key"])
        if given is None:
            raise ProtocolError(f"The {base['title']} station is missing. All five stations are required.")
        steps_in = given.get("steps")
        if not isinstance(steps_in, list) or not steps_in:
            raise ProtocolError(f"{base['title']} needs at least one step.")
        if len(steps_in) > MAX_STEPS_PER_STATION:
            raise ProtocolError(f"{base['title']} has more than {MAX_STEPS_PER_STATION} steps. Split or shorten them.")
        steps = []
        for i, step in enumerate(steps_in, start=1):
            text = str((step or {}).get("instruction", "")).strip()
            if not text:
                raise ProtocolError(f"{base['title']} step {i} has no instruction.")
            if len(text) > MAX_INSTRUCTION_LENGTH:
                raise ProtocolError(f"{base['title']} step {i} is longer than {MAX_INSTRUCTION_LENGTH} characters. "
                                    "It is read aloud, so keep it short.")
            condition = (step or {}).get("condition") or "manual"
            if condition not in CONDITIONS:
                raise ProtocolError(f"{base['title']} step {i} has an unknown check '{condition}'.")
            steps.append({"instruction": text, "condition": condition,
                          "why": str((step or {}).get("why", "")).strip()[:MAX_INSTRUCTION_LENGTH]})
        stations.append({"key": base["key"], "title": base["title"], "steps": steps})

    sheets = []
    for sheet in candidate.get("count_sheets") or standard["count_sheets"]:
        name = str(sheet.get("name", "")).strip()
        if not name:
            raise ProtocolError("Every count sheet needs a name.")
        items = []
        for item in sheet.get("items") or []:
            info = instruments.lookup(str(item.get("key", "")))
            if info is None:
                raise ProtocolError(f"Count sheet '{name}' lists an instrument SPAI can't recognise: {item.get('key')}.")
            count = int(item.get("count", 0))
            if not 0 <= count <= 20:
                raise ProtocolError(f"Count sheet '{name}': {info.name} needs a count from 0 to 20.")
            if count:
                items.append({"key": info.key, "name": info.name, "count": count})
        if not items:
            raise ProtocolError(f"Count sheet '{name}' is empty.")
        sheet_id = str(sheet.get("id") or "").strip() or instruments.key_for(name)
        sheets.append({"id": sheet_id, "name": name, "items": items})

    rubric = dict(scoring.DEFAULT_RUBRIC)
    for key, value in (candidate.get("rubric") or {}).items():
        if key in rubric:
            number = int(value)
            if not 0 <= number <= 100:
                raise ProtocolError(f"Scoring value '{key}' must be between 0 and 100.")
            rubric[key] = number

    return {
        "name": str(candidate.get("name") or "Custom protocol").strip()[:80],
        "stations": stations,
        "count_sheets": sheets,
        "rubric": rubric,
    }


def for_org(org_id: str) -> dict:
    """The protocol a school's headsets follow: its own if an admin has
    edited it, the standard one otherwise. A stored protocol that no longer
    validates (say, after an upgrade) falls back to standard rather than
    leaving students with nothing to do."""
    from app.store import get_store
    saved = get_store().get_protocol(org_id)
    if saved is None:
        return standard_protocol()
    try:
        clean = validate(saved)
    except (ProtocolError, TypeError, ValueError):
        return standard_protocol()
    return {**clean, "version": saved["version"], "updated_at": saved["updated_at"], "is_standard": False}


def save_for_org(org_id: str, candidate: dict, updated_by: str) -> dict:
    from app.store import get_store
    clean = validate(candidate)
    get_store().save_protocol(org_id, clean, updated_by)
    return for_org(org_id)


def reset_for_org(org_id: str) -> dict:
    from app.store import get_store
    get_store().delete_protocol(org_id)
    return standard_protocol()


def steps_for(protocol: dict, station: str) -> list[str] | None:
    for s in protocol["stations"]:
        if s["key"] == station:
            return [step["instruction"] for step in s["steps"]]
    return None
