"""
Tests for the compliance FSM.

Runs the state machine through realistic scenarios and prints the outcome
of each event, so the compliance logic can be seen catching violations.
"""
from app.compliance.engine import ComplianceEngine
from app.compliance.states import WorkflowStep, ComplianceEvent


def show(label: str, result) -> None:
    """Print one event outcome in a readable line."""
    mark = "✓" if result.accepted else "✗"
    print(f"  {mark} {label:<45} → {result.message}")


def scenario_clean_run() -> None:
    """A correct, in-order workflow should be fully accepted."""
    print("\n=== Scenario 1: clean in-order run ===")
    fsm = ComplianceEngine()
    for step in WorkflowStep.ordered():
        show(f"start {step.value}", fsm.process(ComplianceEvent.START_STEP, step))
        show(f"complete {step.value}", fsm.process(ComplianceEvent.COMPLETE_STEP, step))
    print(f"  Final state: {fsm.state.value}")


def scenario_out_of_order() -> None:
    """Skipping ahead should be rejected as a violation."""
    print("\n=== Scenario 2: out-of-order attempt ===")
    fsm = ComplianceEngine()
    # Try to start packaging first — illegal, decontamination must come first.
    show("start packaging (should reject)",
         fsm.process(ComplianceEvent.START_STEP, WorkflowStep.PACKAGING))
    # Correct first step.
    show("start decontamination (ok)",
         fsm.process(ComplianceEvent.START_STEP, WorkflowStep.DECONTAMINATION))


def scenario_contamination() -> None:
    """Contamination halts the workflow until acknowledged."""
    print("\n=== Scenario 3: contamination halt + acknowledge ===")
    fsm = ComplianceEngine()
    show("start decontamination",
         fsm.process(ComplianceEvent.START_STEP, WorkflowStep.DECONTAMINATION))
    show("CONTAMINATION detected",
         fsm.process(ComplianceEvent.CONTAMINATION))
    # Any work while halted should be rejected.
    show("try complete while halted (should reject)",
         fsm.process(ComplianceEvent.COMPLETE_STEP, WorkflowStep.DECONTAMINATION))
    show("acknowledge",
         fsm.process(ComplianceEvent.ACKNOWLEDGE))
    # Now work resumes.
    show("complete decontamination (ok now)",
         fsm.process(ComplianceEvent.COMPLETE_STEP, WorkflowStep.DECONTAMINATION))
    print(f"  Final state: {fsm.state.value}")


if __name__ == "__main__":
    scenario_clean_run()
    scenario_out_of_order()
    scenario_contamination()
    print("\nAll scenarios ran.\n")

    "Run with:  python -m tests.test_compliance   (from the backend folder)"