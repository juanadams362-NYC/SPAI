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
        "Put on your protective gear first — a fluid-resistant mask with eye protection, a gown, and heavy-duty gloves. This keeps splashes and germs off you before you touch anything dirty.",
        "Keep the instruments wet and take apart any that come apart. Dried-on soil is much harder to clean, and hidden surfaces need to be exposed.",
        "Scrub gently under the water line with a soft brush so nothing sprays into the air. For any instrument with a channel inside, brush and flush it through.",
        "Open and unlock any hinged instruments, then load them into the ultrasonic cleaner or washer. Open hinges let the machine clean every surface.",
    ],
    "inspection": [
        "Make sure your gloves are on and your hands are clean before you handle cleaned instruments. This is the point where things need to stay clean.",
        "Look over each instrument under good light and magnification. You're checking for leftover soil, stains, or rust.",
        "Test the moving parts — hinges should open and close smoothly, ratchets should hold, and tips should line up.",
        "Pull anything that fails. Still dirty goes back to decontamination; broken goes to repair.",
    ],
    "tray_assembly": [
        "Check the count sheet — it lists exactly what goes in this tray. Make sure you have the right sheet for the right tray.",
        "Lay the instruments in as the sheet shows: hinges open, tips pointing the same way, and don't overcrowd it. This helps steam reach everything.",
        "Count the instruments and match them to the sheet exactly. The tray also needs to stay under the weight limit.",
        "Add the chemical indicator (it confirms the sterilizer worked) in the spot hardest for steam to reach, then close the tray.",
    ],
    "packaging": [
        "Pick the right wrap or container for the tray's size and weight. If you're unsure, check the instructions for that tray.",
        "Wrap it snugly with no gaps, holes, or thin spots — any opening lets germs back in after sterilizing.",
        "Seal it with indicator tape (never clips or staples, which poke holes) and label it with the contents, date, and your initials.",
    ],
    "seal_validation": [
        "Check the seal all the way around — no gaps, wrinkles, or open channels where germs could get in.",
        "Make sure the indicator on the outside is there and hasn't already changed color.",
        "Confirm the label is complete and easy to read, then send the tray off to be sterilized.",
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
