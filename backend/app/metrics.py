"""
Lightweight in-memory metrics for the health dashboard.

Tracks uptime, total requests, and errors since the server started.
In-memory only — resets on restart, which is fine for a monitoring view.
A production system would use a real metrics store (Prometheus etc.).
"""
import time


class Metrics:
    """Counts requests and errors and tracks server start time."""

    def __init__(self) -> None:
        self.started_at: float = time.time()
        self.request_count: int = 0
        self.error_count: int = 0
        self.detection_count: int = 0

    def record_request(self) -> None:
        self.request_count += 1

    def record_error(self) -> None:
        self.error_count += 1

    def record_detection(self) -> None:
        self.detection_count += 1

    def uptime_seconds(self) -> int:
        return int(time.time() - self.started_at)

    def snapshot(self) -> dict:
        """Current metrics as a plain dict."""
        return {
            "uptime_seconds": self.uptime_seconds(),
            "request_count": self.request_count,
            "error_count": self.error_count,
            "detection_count": self.detection_count,
        }


# Module-level singleton, shared across the app.
metrics = Metrics()
