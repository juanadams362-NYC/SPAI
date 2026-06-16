from __future__ import annotations
"""
The sterile-processing compliance state machine.

Holds the current workflow state and processes events, enforcing legal
transitions. Illegal actions (out-of-order steps, working while halted)
are rejected and recorded as compliance violations. Contamination halts
the workflow until a human acknowledges it.

Pure logic — no model, no hardware, no framework. Fully unit-testable.
"""
from dataclasses import dataclass
from datetime import datetime

from app.compliance.states import (
    WorkflowStep,
    MachineState,
    ComplianceEvent,
)


@dataclass
class TransitionResult:
    """The outcome of processing one event."""
    accepted: bool
    state: MachineState
    current_step: WorkflowStep | None
    message: str


@dataclass
class ComplianceLogEntry:
    """One recorded event in the compliance history."""
    timestamp: str
    event: ComplianceEvent
    accepted: bool
    message: str


class ComplianceEngine:
    """Finite state machine enforcing the sterile-processing workflow."""

    def __init__(self) -> None:
        self.state: MachineState = MachineState.NOT_STARTED
        self.current_step: WorkflowStep | None = None
        self._step_before_halt: WorkflowStep | None = None
        self.log: list[ComplianceLogEntry] = []

    def process(self, event: ComplianceEvent, step: WorkflowStep | None = None) -> TransitionResult:
        """Process an incoming event and return the result.

        `step` is required for START_STEP / COMPLETE_STEP to say which step
        the action refers to; ignored for CONTAMINATION / ACKNOWLEDGE.
        """
        if event == ComplianceEvent.CONTAMINATION:
            result = self._handle_contamination()
        elif event == ComplianceEvent.ACKNOWLEDGE:
            result = self._handle_acknowledge()
        elif event == ComplianceEvent.START_STEP:
            result = self._handle_start(step)
        elif event == ComplianceEvent.COMPLETE_STEP:
            result = self._handle_complete(step)
        else:
            result = self._reject("Unknown event.")

        self._record(event, result)
        return result

    def _handle_start(self, step: WorkflowStep | None) -> TransitionResult:
        if self.state == MachineState.HALTED:
            return self._reject("Workflow halted — acknowledge contamination before continuing.")
        if self.state == MachineState.COMPLETE:
            return self._reject("Workflow already complete.")
        if step is None:
            return self._reject("No step specified to start.")

        expected = self._expected_next_step()
        if step != expected:
            return self._reject(
                f"Out-of-order step. Expected {expected.value}, got {step.value}."
            )

        self.state = MachineState.IN_PROGRESS
        self.current_step = step
        return self._accept(f"Started {step.value}.")

    def _handle_complete(self, step: WorkflowStep | None) -> TransitionResult:
        if self.state == MachineState.HALTED:
            return self._reject("Workflow halted — acknowledge contamination before continuing.")
        if self.state != MachineState.IN_PROGRESS:
            return self._reject("No step in progress to complete.")
        # Capture the active step before any mutation so we never read from None.
        active = self.current_step
        if active is None:
            return self._reject("No step in progress to complete.")
        if step != active:
            return self._reject(
                f"Tried to complete {step.value if step else 'nothing'}, "
                f"but current step is {active.value}."
            )

        # Advance to the next step, or finish the workflow.
        next_step = active.next_step()
        if next_step is None:
            self.state = MachineState.COMPLETE
            self.current_step = None
            return self._accept(f"Completed {active.value}. Workflow complete.")
        else:
            self.state = MachineState.IN_PROGRESS
            self.current_step = None  # next step must be explicitly started
            return self._accept(f"Completed {active.value}.")
        
    def _handle_contamination(self) -> TransitionResult:
        if self.state == MachineState.HALTED:
            return self._reject("Already halted for contamination.")
        self._step_before_halt = self.current_step
        self.state = MachineState.HALTED
        return self._accept("Contamination detected — workflow halted. Acknowledge to resume.")

    def _handle_acknowledge(self) -> TransitionResult:
        if self.state != MachineState.HALTED:
            return self._reject("Nothing to acknowledge — workflow is not halted.")
        self.current_step = self._step_before_halt
        self._step_before_halt = None
        self.state = MachineState.IN_PROGRESS if self.current_step else MachineState.NOT_STARTED
        return self._accept("Contamination acknowledged — workflow resumed.")

    def _expected_next_step(self) -> WorkflowStep:
        """The step that should be started next, based on history."""
        completed_steps = [
            entry for entry in self.log
            if entry.event == ComplianceEvent.COMPLETE_STEP and entry.accepted
        ]
        return WorkflowStep.ordered()[len(completed_steps)]

    def _accept(self, message: str) -> TransitionResult:
        return TransitionResult(True, self.state, self.current_step, message)

    def _reject(self, message: str) -> TransitionResult:
        return TransitionResult(False, self.state, self.current_step, message)

    def _record(self, event: ComplianceEvent, result: TransitionResult) -> None:
        self.log.append(ComplianceLogEntry(
            timestamp=datetime.now().isoformat(timespec="seconds"),
            event=event,
            accepted=result.accepted,
            message=result.message,
        ))