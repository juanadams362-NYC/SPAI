"""
Who is allowed to call what.

Three kinds of caller, each proving who they are differently:

  Headset     A paired Vision Pro. Sends `Authorization: Bearer <token>`.
              The token was issued once, when an admin's pairing code was
              entered on the headset; it belongs to one organization and can
              be revoked from the dashboard at any time.

  Instructor  A person signed in to the dashboard with email and password.
              Holds an HttpOnly session cookie. Admins can also manage
              headsets, instructors, the protocol and deletions.

  Operator    Whoever runs the server (SPAI). Sends `X-SPAI-Operator` matching
              the SPAI_OPERATOR_KEY environment variable. Only needed for
              settings that affect every school on the server.

There is no "open" mode. Every route that touches a school's data needs a
headset token or an instructor login for that school.
"""
from __future__ import annotations

import hmac
import os
import threading
import time
from collections import defaultdict, deque

from fastapi import Depends, Header, HTTPException, Request

from app.store import get_store

COOKIE_NAME = "spai_session"


# --- Rate limiting --------------------------------------------------------------

class RateLimiter:
    """At most `limit` attempts per key in a sliding `window` of seconds.

    In memory, so it resets on restart and is per process. That is enough to
    make guessing a password, a PIN or a pairing code impractical; the stored
    lockouts (PINs) and single-use codes cover the rest.
    """

    def __init__(self, limit: int, window: float) -> None:
        self.limit, self.window = limit, window
        self._hits: dict[str, deque] = defaultdict(deque)
        self._lock = threading.Lock()

    def hit(self, key: str) -> bool:
        """Record an attempt. False means the caller has used up their tries."""
        now = time.monotonic()
        with self._lock:
            q = self._hits[key]
            while q and now - q[0] > self.window:
                q.popleft()
            if len(q) >= self.limit:
                return False
            q.append(now)
            return True

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


login_limiter = RateLimiter(limit=8, window=300)      # per email and per address
pairing_limiter = RateLimiter(limit=10, window=300)   # per address
pin_limiter = RateLimiter(limit=20, window=300)       # per headset, on top of the per-learner lockout


def client_address(request: Request) -> str:
    return request.client.host if request.client else "unknown"


# --- Headsets -------------------------------------------------------------------

def current_device(authorization: str | None = Header(default=None)) -> dict:
    token = ""
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()
    device = get_store().device_for_token(token)
    if device is None:
        raise HTTPException(
            status_code=401,
            detail="This headset isn't connected to a school, or was disconnected. Pair it again from Settings.",
        )
    return device


# --- Instructors ----------------------------------------------------------------

def current_instructor(request: Request) -> dict:
    instructor = get_store().instructor_for_login(request.cookies.get(COOKIE_NAME))
    if instructor is None:
        raise HTTPException(status_code=401, detail="Sign in to the instructor dashboard first.")
    # Requests that change something must come from this site's own pages.
    # The cookie is SameSite=Strict as well; this is the second lock.
    if request.method not in ("GET", "HEAD", "OPTIONS"):
        origin = request.headers.get("origin")
        if origin and origin.rstrip("/") != str(request.base_url).rstrip("/"):
            raise HTTPException(status_code=403, detail="That request didn't come from the SPAI dashboard.")
    return instructor


def require_admin(instructor: dict = Depends(current_instructor)) -> dict:
    if instructor["role"] != "admin":
        raise HTTPException(status_code=403, detail="Only an admin can do that. Ask your program's SPAI admin.")
    return instructor


def is_https(request: Request) -> bool:
    # Behind a proxy (most hosts), the original scheme arrives in a header.
    return request.url.scheme == "https" or request.headers.get("x-forwarded-proto", "").split(",")[0].strip() == "https"


# --- Operator -------------------------------------------------------------------

def require_operator(x_spai_operator: str | None = Header(default=None)) -> None:
    expected = os.getenv("SPAI_OPERATOR_KEY")
    if not expected or not x_spai_operator or not hmac.compare_digest(x_spai_operator, expected):
        raise HTTPException(status_code=403, detail="Only the server operator can change this.")
