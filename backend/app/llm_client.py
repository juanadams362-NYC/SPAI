"""
llm_client.py — the only file in SPAI that knows which LLM provider we use.
Swap providers by editing this file only. The rest of the backend just
calls ask_llm(system, prompt) and gets text back.
"""

import os
import requests

GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.1-flash-lite")
GEMINI_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    f"{GEMINI_MODEL}:generateContent"
)


class LLMError(Exception):
    """Raised when the LLM call fails for any reason."""


def ask_llm(system_prompt: str, user_prompt: str, timeout: int = 20) -> str:
    """Send a prompt to Gemini, return the text answer."""
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise LLMError("GEMINI_API_KEY is not set")

    payload = {
        "system_instruction": {"parts": [{"text": system_prompt}]},
        "contents": [{"parts": [{"text": user_prompt}]}],
        "generationConfig": {"temperature": 0.2, "maxOutputTokens": 300},
    }

    try:
        resp = requests.post(
            GEMINI_URL,
            params={"key": api_key},
            json=payload,
            timeout=timeout,
        )
    except requests.RequestException as e:
        raise LLMError(f"Could not reach Gemini: {e}") from e

    if resp.status_code != 200:
        raise LLMError(f"Gemini returned {resp.status_code}: {resp.text[:200]}")

    try:
        return resp.json()["candidates"][0]["content"]["parts"][0]["text"].strip()
    except (KeyError, IndexError) as e:
        raise LLMError(f"Unexpected Gemini response shape: {resp.text[:200]}") from e


if __name__ == "__main__":
    # Standalone smoke test: python3 llm_client.py
    print(ask_llm(
        "You are a test assistant. Answer in five words or less.",
        "Say hello to SPAI.",
    ))
