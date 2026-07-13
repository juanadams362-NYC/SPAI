"""
ask_spai.py — prompt builder for the /ask endpoint.
Station scripts live here for now, guided sim will reuse this same
data so only write the steps once. Wording gets fleshed out later
when all 5 stations get real content.
"""

from app.llm_client import ask_llm, LLMError

# Step scripts per station. Short placeholder wording for now.
# Keys have to match the app's station names exactly or lookup fails.
STATION_SCRIPTS = {
    "decontamination": [
        "Verify PPE: gloves, gown, eye protection on before touching anything.",
        "Manual clean: keep instruments at the sink, brush below the waterline so soil never aerosolizes.",
        "Rinse thoroughly with treated water, keeping instruments low in the basin.",
        "Load instruments open and unlocked into the washer, hinged side down.",
    ],
    "inspection": [
        "Confirm hands are clean and gloves are fresh before handling processed instruments.",
        "Inspect each instrument under light and magnification for soil, damage, and corrosion.",
        "Function-test moving parts: hinges open smooth, ratchets hold, tips align.",
        "Set aside anything that fails: soiled goes back to decontam, damaged goes to repair.",
    ],
    "tray_assembly": [
        "Verify the count sheet matches the tray you are building.",
        "Place instruments per the count sheet, heavy items on the bottom, ring-handled instruments open on stringers.",
        "Confirm the instrument count matches the sheet exactly.",
        "Place the internal chemical indicator and close the tray.",
    ],
    "prep_and_pack": [
        "Select the correct wrap or container size for the tray weight.",
        "Wrap using the correct fold technique with no gaps or tears.",
        "Secure with indicator tape and label with contents, date, and initials.",
    ],
    "seal_validation": [
        "Inspect the package seal for complete closure with no channels or wrinkles.",
        "Verify the external indicator is present and unexposed.",
        "Confirm the label is complete and legible, then release to sterile storage.",
    ],
}

# Guardrails: user is wearing a Vision Pro mid-task — gloved hands,
# reading a floating panel, can't type or scroll. Answers must be
# glanceable and hands-free friendly. Only answer from injected steps,
# never improvise procedure.
SYSTEM_PROMPT = """You are SPAI, a training assistant for sterile processing department (SPD) technicians.
The user is wearing an Apple Vision Pro headset while actively working. Their hands are gloved and busy with instruments. They are reading your answer on a floating panel and cannot type, scroll, or touch anything outside their work.
Keep answers to 2-3 short sentences, plain language, immediately actionable from where they are standing.
Never tell the user to touch the headset, remove gloves, use a phone or computer, or look anything up.
Base your answer ONLY on the station steps and live detection state provided in each message.
If the question cannot be answered from the provided steps, say you are not sure and tell them to ask their supervisor out loud.
Never invent sterile processing procedure. Never tell the user to skip a step."""


def build_context(station: str, step_index: int, detection_summary: str, question: str) -> str:
    # Everything the model needs, packed into one prompt string.
    steps = STATION_SCRIPTS.get(station)
    if steps is None:
        known = ", ".join(STATION_SCRIPTS)
        raise ValueError(f"Unknown station '{station}'. Known stations: {known}")

    # Clamp so a bad step index from the app degrades instead of crashing.
    step_index = max(0, min(step_index, len(steps) - 1))

    # >> points at the current step so the model doesn't have to count.
    numbered = "\n".join(
        f"{i + 1}. {'>> ' if i == step_index else ''}{s}"
        for i, s in enumerate(steps)
    )

    return (
        f"Station: {station.replace('_', ' ').title()}\n"
        f"Steps for this station (>> marks the user's current step):\n{numbered}\n"
        f"Current step: {step_index + 1} of {len(steps)}\n"
        f"Live detection state: {detection_summary or 'no detections reported'}\n\n"
        f"User question: {question}"
    )


def ask_spai(station: str, step_index: int, detection_summary: str, question: str) -> str:
    prompt = build_context(station, step_index, detection_summary, question)
    return ask_llm(SYSTEM_PROMPT, prompt)


if __name__ == "__main__":
    # Quick check with the question that started this whole feature.
    print(ask_spai(
        station="decontamination",
        step_index=1,
        detection_summary="gloves detected, no bare hand, 2 instruments detected",
        question="what do I do with what's in my hands?",
    ))
