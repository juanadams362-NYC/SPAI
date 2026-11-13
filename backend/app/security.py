"""
Who is allowed to call what.

Two secrets, both set as environment variables on the server:

  SPAI_API_KEY         shared by the headsets. Sent as the X-SPAI-Key header.
  SPAI_INSTRUCTOR_PIN  typed by an instructor to open the dashboard.

If neither is set the server runs open, which is right for a laptop on a
desk and wrong for anything on the internet. The dashboard says so in a
banner, and /health/stats reports it, so an unsecured deployment is never
a surprise.
"""
from __future__ import annotations

import hashlib
import hmac
import os
import secrets

from fastapi import Cookie, Header, HTTPException

COOKIE_NAME = "spai_instructor"

# Signs instructor cookies. Regenerated on restart unless SPAI_SECRET is set,
# which only means instructors sign in again after a redeploy.
_SECRET = (os.getenv("SPAI_SECRET") or secrets.token_hex(32)).encode()


def api_key() -> str | None:
    return os.getenv("SPAI_API_KEY") or None


def instructor_pin() -> str | None:
    return os.getenv("SPAI_INSTRUCTOR_PIN") or None


def is_secured() -> dict:
    return {"headset_key": api_key() is not None, "instructor_pin": instructor_pin() is not None}


def _same(a: str, b: str) -> bool:
    return hmac.compare_digest(a.encode(), b.encode())


def instructor_token() -> str:
    """Cookie value proving the PIN was entered. Changes if the PIN changes."""
    return hmac.new(_SECRET, (instructor_pin() or "").encode(), hashlib.sha256).hexdigest()


def check_pin(pin: str) -> bool:
    expected = instructor_pin()
    return expected is None or _same(pin, expected)


def _is_instructor(cookie: str | None) -> bool:
    return instructor_pin() is None or (cookie is not None and _same(cookie, instructor_token()))


def require_headset(
    x_spai_key: str | None = Header(default=None),
    spai_instructor: str | None = Cookie(default=None),
) -> None:
    """Routes the headsets call. A signed-in instructor is also let through,
    so the dashboard can read the same data."""
    expected = api_key()
    if expected is None:
        return
    if x_spai_key and _same(x_spai_key, expected):
        return
    if instructor_pin() is not None and _is_instructor(spai_instructor):
        return
    raise HTTPException(status_code=401, detail="Missing or wrong access key. Enter this site's key in SPAI Settings.")


def require_instructor(spai_instructor: str | None = Cookie(default=None)) -> None:
    if not _is_instructor(spai_instructor):
        raise HTTPException(status_code=401, detail="Sign in to the instructor dashboard first.")
