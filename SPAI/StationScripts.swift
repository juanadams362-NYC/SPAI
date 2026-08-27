//
//  StationScripts.swift
//  SPAI
//
//  Created by AVP Student on 7/14/26.
//

import Foundation

enum StepCondition {
    case glovesOn
    case instrumentsPresent
    case trayLoaded
    case manual
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
            GuidedStep(instruction: "Put on your protective gear first — a fluid-resistant mask with eye protection, a gown, and heavy-duty gloves. This keeps splashes and germs off you before you touch anything dirty.",
                       condition: .glovesOn),
            GuidedStep(instruction: "Keep the instruments wet and take apart any that come apart. Dried-on soil is much harder to clean, and hidden surfaces need to be exposed.",
                       condition: .instrumentsPresent),
            GuidedStep(instruction: "Scrub gently under the water line with a soft brush so nothing sprays into the air. For any instrument with a channel inside, brush and flush it through.",
                       condition: .manual),
            GuidedStep(instruction: "Open and unlock any hinged instruments, then load them into the ultrasonic cleaner or washer. Open hinges let the machine clean every surface.",
                       condition: .manual),
        ]
        case .inspection: return [
            GuidedStep(instruction: "Make sure your gloves are on and your hands are clean before you handle cleaned instruments. This is the point where things need to stay clean.",
                       condition: .glovesOn),
            GuidedStep(instruction: "Look over each instrument under good light and magnification. You're checking for leftover soil, stains, or rust.",
                       condition: .instrumentsPresent),
            GuidedStep(instruction: "Test the moving parts — hinges should open and close smoothly, ratchets should hold, and tips should line up.",
                       condition: .manual),
            GuidedStep(instruction: "Pull anything that fails. Still dirty goes back to decontamination; broken goes to repair.",
                       condition: .manual),
        ]
        case .trayAssembly: return [
            GuidedStep(instruction: "Check the count sheet — it lists exactly what goes in this tray. Make sure you have the right sheet for the right tray.",
                       condition: .manual),
            GuidedStep(instruction: "Lay the instruments in as the sheet shows: hinges open, tips pointing the same way, and don't overcrowd it. This helps steam reach everything.",
                       condition: .trayLoaded),
            GuidedStep(instruction: "Count the instruments and match them to the sheet exactly. The tray also needs to stay under the weight limit.",
                       condition: .instrumentsPresent),
            GuidedStep(instruction: "Add the chemical indicator (it confirms the sterilizer worked) in the spot hardest for steam to reach, then close the tray.",
                       condition: .manual),
        ]
        case .packaging: return [
            GuidedStep(instruction: "Pick the right wrap or container for the tray's size and weight. If you're unsure, check the instructions for that tray.",
                       condition: .manual),
            GuidedStep(instruction: "Wrap it snugly with no gaps, holes, or thin spots — any opening lets germs back in after sterilizing.",
                       condition: .manual),
            GuidedStep(instruction: "Seal it with indicator tape (never clips or staples, which poke holes) and label it with the contents, date, and your initials.",
                       condition: .manual),
        ]
        case .sealValidation: return [
            GuidedStep(instruction: "Check the seal all the way around — no gaps, wrinkles, or open channels where germs could get in.",
                       condition: .manual),
            GuidedStep(instruction: "Make sure the indicator on the outside is there and hasn't already changed color.",
                       condition: .manual),
            GuidedStep(instruction: "Check that the label is complete and easy to read, then send the tray off to be sterilized.",
                       condition: .manual),
        ]
        }
    }
}
