//
//  StationScripts.swift
//  SPAI
//
//  Created by AVP Student on 7/14/26.
//  The guided-sim step scripts. One source of truth for what each
//  station's steps are and what detection state satisfies each one.
//  Mirrors ask_spai.py on the backend — if a step changes, change both.
//

import Foundation

/// What live detection state marks a guided step as verified.
enum StepCondition {
    case glovesOn            // glove detected, no bare hand
    case instrumentsPresent  // at least one instrument detected
    case trayLoaded          // tray state == loaded
    case manual              // no detection can verify this — user confirms
}

struct GuidedStep: Identifiable {
    let id = UUID()
    let instruction: String
    let condition: StepCondition
}

enum StationScripts {
    static func script(for step: SterileStep) -> [GuidedStep] {
        switch step {
        case .decontamination: return [
            GuidedStep(instruction: "Put on PPE: gloves, gown, and eye protection before touching anything.",
                       condition: .glovesOn),
            GuidedStep(instruction: "Manual clean: keep instruments at the sink, brush below the waterline so soil never aerosolizes.",
                       condition: .manual),
            GuidedStep(instruction: "Rinse thoroughly with treated water, keeping instruments low in the basin.",
                       condition: .manual),
            GuidedStep(instruction: "Load instruments open and unlocked into the washer, hinged side down.",
                       condition: .manual),
        ]
        case .inspection: return [
            GuidedStep(instruction: "Confirm hands are clean and gloves are fresh before handling processed instruments.",
                       condition: .glovesOn),
            GuidedStep(instruction: "Inspect each instrument under light and magnification for soil, damage, and corrosion.",
                       condition: .instrumentsPresent),
            GuidedStep(instruction: "Function-test moving parts: hinges open smooth, ratchets hold, tips align.",
                       condition: .manual),
            GuidedStep(instruction: "Set aside anything that fails: soiled goes back to decontam, damaged goes to repair.",
                       condition: .manual),
        ]
        case .trayAssembly: return [
            GuidedStep(instruction: "Verify the count sheet matches the tray you are building.",
                       condition: .manual),
            GuidedStep(instruction: "Place instruments per the count sheet: heavy items on the bottom, ring-handled instruments open on stringers.",
                       condition: .trayLoaded),
            GuidedStep(instruction: "Confirm the instrument count matches the sheet exactly.",
                       condition: .instrumentsPresent),
            GuidedStep(instruction: "Place the internal chemical indicator and close the tray.",
                       condition: .manual),
        ]
        case .packaging: return [
            GuidedStep(instruction: "Select the correct wrap or container size for the tray weight.",
                       condition: .manual),
            GuidedStep(instruction: "Wrap using the correct fold technique with no gaps or tears.",
                       condition: .manual),
            GuidedStep(instruction: "Secure with indicator tape and label with contents, date, and initials.",
                       condition: .manual),
        ]
        case .sealValidation: return [
            GuidedStep(instruction: "Inspect the package seal for complete closure with no channels or wrinkles.",
                       condition: .manual),
            GuidedStep(instruction: "Verify the external indicator is present and unexposed.",
                       condition: .manual),
            GuidedStep(instruction: "Confirm the label is complete and legible, then release to sterile storage.",
                       condition: .manual),
        ]
        }
    }
}
