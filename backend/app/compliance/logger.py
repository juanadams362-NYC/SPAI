"""
Compliance trail export.

Takes the event log produced by the ComplianceEngine and writes it to disk
in two forms: a structured JSON file for the app to parse, and a plain-text
log for a human to read. Kept separate from the engine — the engine owns
the state logic, this owns persistence.
"""
import json
from dataclasses import asdict
from datetime import datetime
from pathlib import Path

from app.compliance.engine import ComplianceLogEntry
from app.logging_config import get_logger

logger = get_logger(__name__)

# Where compliance trails are written. Created if it doesn't exist.
LOG_DIR = Path(__file__).parent.parent.parent / "compliance_logs"


class ComplianceLogger:
    """Exports a compliance event log to JSON and plain text."""

    def __init__(self, log_dir: Path = LOG_DIR) -> None:
        self.log_dir = log_dir
        self.log_dir.mkdir(parents=True, exist_ok=True)

    def export(self, entries: list[ComplianceLogEntry], session_id: str | None = None) -> dict:
        """Write the given log entries to both a JSON and a text file.

        Returns a small summary dict with the file paths and counts so the
        caller (an API endpoint, say) can report what was written.
        """
        # Name files by session, or by timestamp if no session id is given.
        stamp = session_id or datetime.now().strftime("%Y%m%d_%H%M%S")
        json_path = self.log_dir / f"compliance_{stamp}.json"
        text_path = self.log_dir / f"compliance_{stamp}.txt"

        self._write_json(entries, json_path)
        self._write_text(entries, text_path)

        # Count how many events were violations (rejected) for a quick summary.
        violations = sum(1 for e in entries if not e.accepted)

        logger.info(
            "Compliance trail exported: %d events (%d violations) -> %s",
            len(entries), violations, json_path.name,
        )

        return {
            "events": len(entries),
            "violations": violations,
            "json_file": str(json_path),
            "text_file": str(text_path),
        }

    def _write_json(self, entries: list[ComplianceLogEntry], path: Path) -> None:
        # asdict turns each dataclass entry into a plain dict; enums serialize
        # to their string values because they inherit from str.
        data = [self._entry_to_dict(e) for e in entries]
        path.write_text(json.dumps(data, indent=2))

    def _write_text(self, entries: list[ComplianceLogEntry], path: Path) -> None:
        lines = ["SPAI Compliance Trail", "=" * 40, ""]
        for e in entries:
            mark = "OK " if e.accepted else "VIOLATION"
            lines.append(f"[{e.timestamp}] {mark:<10} {e.event.value:<15} {e.message}")
        lines.append("")
        lines.append(f"Total events: {len(entries)}")
        lines.append(f"Violations: {sum(1 for e in entries if not e.accepted)}")
        path.write_text("\n".join(lines))

    def _entry_to_dict(self, entry: ComplianceLogEntry) -> dict:
        """Convert one log entry to a JSON-safe dict."""
        return {
            "timestamp": entry.timestamp,
            "event": entry.event.value,
            "accepted": entry.accepted,
            "message": entry.message,
        }