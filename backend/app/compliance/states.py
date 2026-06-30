from __future__ import annotations
"""
States and events for the sterile-processing compliance FSM.

Defines the vocabulary the state machine works with: the workflow steps,
the overall machine states, and the events that drive transitions.
Kept separate from the engine so the types are easy to read and test.
"""
from enum import Enum


class WorkflowStep(str, Enum):
    """The five sterile-processing steps, in required order."""
    DECONTAMINATION = "decontamination"
    INSPECTION = "inspection"
    TRAY_ASSEMBLY = "tray_assembly"
    PACKAGING = "packaging"
    SEAL_VALIDATION = "seal_validation"

    @classmethod
    def ordered(cls) -> list["WorkflowStep"]:
        """The steps in the order they must be performed."""
        return [
            cls.DECONTAMINATION,
            cls.INSPECTION,
            cls.TRAY_ASSEMBLY,
            cls.PACKAGING,
            cls.SEAL_VALIDATION,
        ]

    def next_step(self) -> "WorkflowStep | None":
        """The step that legally follows this one, or None if this is the last."""
        order = WorkflowStep.ordered()
        index = order.index(self)
        if index + 1 < len(order):
            return order[index + 1]
        return None


class MachineState(str, Enum):
    """The overall state of the compliance machine."""
    NOT_STARTED = "not_started"   # nothing has begun
    IN_PROGRESS = "in_progress"   # actively working a step
    HALTED = "halted"             # contamination detected — frozen pending acknowledgment
    COMPLETE = "complete"         # all steps finished


class ComplianceEvent(str, Enum):
    """Events that can drive a transition in the machine."""
    START_STEP = "start_step"
    COMPLETE_STEP = "complete_step"
    CONTAMINATION = "contamination"
    ACKNOWLEDGE = "acknowledge"   # human clears a halt to resume
    