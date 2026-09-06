//
//  DetectionTuning.swift
//  SPAI
//

import Foundation

/// Single source of truth for how detections are accepted or rejected.
///
/// This exists because the cloud path and the on-device path had drifted apart: the backend
/// filtered at the threshold in Settings (0.25 by default) while `OnDeviceDetector` had 0.5
/// hard-coded and ignored the setting entirely. Since the app silently falls back from cloud to
/// on-device whenever the backend is unreachable, two machines pointed at different backends —
/// or one with a typo in its URL — would quietly run *different models at different thresholds*
/// and disagree about the same scene. That is the "works on my home Mac, iffy in the lab" bug,
/// and it was configuration drift rather than the model.
enum DetectionTuning {

    // MARK: - Confidence

    /// Floor for glove/hand detections.
    ///
    /// PPE is the safety signal, so this stays permissive: missing a bare hand is worse than
    /// briefly flagging one, and the guided step already requires several consecutive
    /// confirmations before it acts.
    static let ppeConfidence: Double = 0.25

    /// Floor for instrument detections — deliberately much higher than PPE.
    ///
    /// The instrument model has six classes and no "background" class, so anything you point it
    /// at gets forced into one of them. A chair is not a near-miss for a scalpel; it is simply
    /// out of distribution, and the model answers anyway. Out-of-distribution objects tend to
    /// come back with middling confidence, so raising the bar here is what separates "that is
    /// really an instrument" from "that is furniture".
    static let instrumentConfidence: Double = 0.55

    // MARK: - Geometry

    /// Largest fraction of the frame a single instrument may occupy.
    ///
    /// Instruments are photographed lying in a tray: even a long pair of scissors is a modest
    /// slice of the image. A chair, a bench, or a person fills it. This one check removes most
    /// furniture false positives without touching the model.
    static let maxInstrumentAreaFraction: Double = 0.35

    /// Smallest fraction of the frame worth believing, to drop single-pixel noise.
    static let minInstrumentAreaFraction: Double = 0.0005

    /// Largest fraction of the frame a glove or hand may occupy. Hands can legitimately fill a
    /// lot of a close-up frame, so this is far more generous than the instrument limit.
    static let maxPPEAreaFraction: Double = 0.90

    // MARK: - Stability

    /// Consecutive clean frames required before a raised contamination risk is allowed to drop.
    ///
    /// Deliberately asymmetric. Risk **escalates on the very first frame** that shows a bare
    /// hand — a safety signal must never wait for confirmation, and an earlier version of this
    /// smoothing delayed the alert by requiring two frames in both directions, which is the
    /// wrong trade for the one thing in this app that protects a patient.
    ///
    /// Clearing is where the smoothing belongs: a single frame where the hand happens to be
    /// occluded should not silently cancel a real alert, and it is also what made the readout
    /// flicker during testing.
    static let clearFrameCount: Int = 3

    // MARK: - Class vocabulary

    /// Vocabulary that identifies a detection as a surgical instrument.
    ///
    /// `isInstrumentClass` used to be defined as "not a glove and not a hand", which meant any
    /// unexpected string — a relabelled class, a future model with new outputs, a stub response
    /// — silently counted as an instrument and could satisfy a workflow step. That is how a
    /// chair passed an inspection step.
    ///
    /// Matched as terms rather than whole labels on purpose. The backend relabels everything to
    /// "instrument" while the on-device model emits full names like "Adson Dressing Forceps",
    /// and a shortened or re-cased variant from either side should still count. An exact-match
    /// list would quietly start ignoring real instruments the first time a label changed —
    /// failing closed on a workflow step, which is worse than the chair it was guarding against.
    static let instrumentTerms: [String] = [
        "instrument",
        "forceps", "scissors", "scalpel", "needle holder", "hemostat", "clamp",
        "retractor", "curette", "rongeur", "osteotome", "elevator", "dilator",
        "speculum", "probe", "trocar", "cannula", "suction", "towel clip"
    ]

    /// Whether a label names something that belongs in a tray.
    static func isInstrumentLabel(_ className: String) -> Bool {
        let name = normalized(className)
        guard !name.isEmpty else { return false }
        return instrumentTerms.contains { name.contains($0) }
    }

    /// What every instrument detection is reported as.
    ///
    /// The model nominally has six classes but in practice collapses to one, so the specific
    /// name is misleading — the backend already relabels for this reason and the on-device path
    /// did not, which is why the same tray could read "Adson Dressing Forceps" locally and
    /// "instrument" through the cloud.
    static let instrumentDisplayLabel = "instrument"

    // MARK: - Helpers

    static func normalized(_ className: String) -> String {
        className.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Whether a box is a plausible size for what it claims to be.
    /// `box` is `[x1, y1, x2, y2]` in pixels.
    static func isPlausible(box: [Int], imageWidth: Int, imageHeight: Int, isInstrument: Bool) -> Bool {
        guard box.count == 4, imageWidth > 0, imageHeight > 0 else { return false }

        let w = Double(abs(box[2] - box[0]))
        let h = Double(abs(box[3] - box[1]))
        guard w > 0, h > 0 else { return false }

        let frame = Double(imageWidth) * Double(imageHeight)
        let fraction = (w * h) / frame

        if isInstrument {
            return fraction >= minInstrumentAreaFraction && fraction <= maxInstrumentAreaFraction
        }
        return fraction > 0 && fraction <= maxPPEAreaFraction
    }
}
