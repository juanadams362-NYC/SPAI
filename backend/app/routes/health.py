"""Health endpoints — basic check, JSON stats, and an HTML dashboard."""
from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from app.inference.detector import detector
from app.metrics import metrics

router = APIRouter()


@router.get("/health")
def health() -> dict:
    """Basic liveness check. Used by the app to verify the backend is reachable."""
    return {"status": "ok"}


@router.get("/health/stats")
def health_stats() -> dict:
    """Detailed status: model state plus runtime metrics."""
    return {
        "status": "ok",
        "model": detector.status(),
        "metrics": metrics.snapshot(),
    }


def _format_uptime(seconds: int) -> str:
    """Turn a second count into a readable h/m/s string."""
    hours, rem = divmod(seconds, 3600)
    minutes, secs = divmod(rem, 60)
    return f"{hours}h {minutes}m {secs}s"


@router.get("/health/dashboard", response_class=HTMLResponse)
def health_dashboard() -> str:
    """A simple visual status page for the backend."""
    model = detector.status()
    snap = metrics.snapshot()
    mode = model["mode"]
    mode_color = "#2ecc71" if mode == "real" else "#f39c12"

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>SPAI Backend Status</title>
  <style>
    body {{ font-family: -apple-system, system-ui, sans-serif; background: #0d1117;
            color: #e6edf3; margin: 0; padding: 40px; }}
    h1 {{ font-weight: 600; }}
    .grid {{ display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; max-width: 640px; }}
    .card {{ background: #161b22; border: 1px solid #30363d; border-radius: 12px; padding: 20px; }}
    .label {{ color: #8b949e; font-size: 13px; text-transform: uppercase; letter-spacing: 1px; }}
    .value {{ font-size: 28px; font-weight: 700; margin-top: 6px; }}
    .badge {{ display: inline-block; padding: 4px 12px; border-radius: 999px;
              font-weight: 700; color: #0d1117; background: {mode_color}; }}
  </style>
</head>
<body>
  <h1>SPAI Backend Status</h1>
  <p>Model mode: <span class="badge">{mode.upper()}</span></p>
  <div class="grid">
    <div class="card"><div class="label">Uptime</div><div class="value">{_format_uptime(snap['uptime_seconds'])}</div></div>
    <div class="card"><div class="label">Total Requests</div><div class="value">{snap['request_count']}</div></div>
    <div class="card"><div class="label">Detections Run</div><div class="value">{snap['detection_count']}</div></div>
    <div class="card"><div class="label">Errors</div><div class="value">{snap['error_count']}</div></div>
    <div class="card"><div class="label">Confidence Threshold</div><div class="value">{model.get('confidence_threshold', 'n/a')}</div></div>
    <div class="card"><div class="label">Classes</div><div class="value">{', '.join(model['classes'])}</div></div>
  </div>
</body>
</html>"""
