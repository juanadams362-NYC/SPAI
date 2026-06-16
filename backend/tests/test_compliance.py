"""
Tests for the compliance FSM.

Runs the state machine through realistic scenarios and prints the outcome
of each event, so the compliance logic can be seen catching violations.
Run with:  python -m tests.test_compliance   (from the backend folder)
"""
from app.compliance.engine import ComplianceEngine
from app.compliance.states import WorkflowStep, ComplianceEvent


def show(label: str, result) -> None:
    mark = "✓" if result.accepted else "✗"
    print(f"  {mark} {label:<45} → {result.message}")


def scenario_clean_run() -> None:
    print("\n=== Scenario 1: clean in-order run ===")
    fsm = ComplianceEngine()
    for step in WorkflowStep.ordered():
        show(f"start {step.value}", fsm.process(ComplianceEvent.START_STEP, step))
        show(f"complete {step.value}", fsm.process(ComplianceEvent.COMPLETE_STEP, step))
    print(f"  Final state: {fsm.state.value}")


def scenario_out_of_order() -> None:
    print("\n=== Scenario 2: out-of-order attempt ===")
    fsm = ComplianceEngine()
    show("start packaging (should reject)",
         fsm.process(ComplianceEvent.START_STEP, WorkflowStep.PACKAGING))
    show("start decontamination (ok)",
         fsm.process(ComplianceEvent.START_STEP, WorkflowStep.DECONTAMINATION))


def scenario_contamination() -> None:
    print("\n=== Scenario 3: contamination halt + acknowledge ===")
    fsm = ComplianceEngine()
    show("start decontamination",
         fsm.process(ComplianceEvent.START_STEP, WorkflowStep.DECONTAMINATION))
    show("CONTAMINATION detected",
         fsm.process(ComplianceEvent.CONTAMINATION))
    show("try complete while halted (should reject)",
         fsm.process(ComplianceEvent.COMPLETE_STEP, WorkflowStep.DECONTAMINATION))
    show("acknowledge",
         fsm.process(ComplianceEvent.ACKNOWLEDGE))
    show("complete decontamination (ok now)",
         fsm.process(ComplianceEvent.COMPLETE_STEP, WorkflowStep.DECONTAMINATION))
    print(f"  Final state: {fsm.state.value}")


def scenario_export() -> None:
    print("\n=== Scenario 4: export compliance trail ===")
    from app.compliance.logger import ComplianceLogger

    fsm = ComplianceEngine()
    fsm.process(ComplianceEvent.START_STEP, WorkflowStep.PACKAGING)
    fsm.process(ComplianceEvent.START_STEP, WorkflowStep.DECONTAMINATION)
    fsm.process(ComplianceEvent.CONTAMINATION)
    fsm.process(ComplianceEvent.ACKNOWLEDGE)

    summary = ComplianceLogger().export(fsm.log, session_id="test_session")
    print(f"  Exported {summary['events']} events, {summary['violations']} violations")
    print(f"  JSON: {summary['json_file']}")
    print(f"  Text: {summary['text_file']}")


if __name__ == "__main__":
    scenario_clean_run()
    scenario_out_of_order()
    scenario_contamination()
    scenario_export()
    print("\nAll scenarios ran.\n")
