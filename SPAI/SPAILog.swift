//
//  SPAILog.swift
//  SPAI
//

import Foundation
import os

/// Routes the app's diagnostic output through one switch instead of ~50 loose `print` calls.
///
/// Two things pushed this into existence. A device session's console is dense enough that the
/// line you actually need — the measured eye height, say — scrolls past between ARKit's own
/// chatter and the per-frame detection counts. And `print` leaves nothing to read back: a
/// tester wearing the device is not attached to Xcode, so anything that only reaches stdout is
/// gone the moment it scrolls.
///
/// So everything goes through `os.Logger`, which Console.app can filter by subsystem and
/// category and which outlives the run, and the chatty levels sit behind the Debug section in
/// Settings.
///
/// Failures are deliberately *not* gated. A toggle being off must never be the reason you
/// cannot see why something broke — that is the exact situation where you are least likely to
/// be able to reproduce it on demand and flip the switch.
enum SPAILog {
    /// Mirrors the bracketed prefixes the old `print` calls used, so existing console filters
    /// and muscle memory keep working. The category is recorded by `Logger` itself, which is
    /// why the call sites no longer repeat it in the message text.
    enum Category: String, CaseIterable, Sendable {
        case headAnchor    = "head-anchor"
        case handTracking  = "hand-tracking"
        case detection     = "detection"
        case onDeviceModel = "on-device-model"
        case video         = "video"
        case upload        = "upload"
        case stations      = "stations"
        case sound         = "sound"
        case speech        = "speech"
        case environment   = "environment"
        case ui            = "ui"
        case camera        = "camera"
    }

    /// Defaults key, shared with `@AppStorage` in SettingsView — the same split `speakSteps`
    /// already uses, so that services can read a setting without owning a view.
    static let debugLoggingKey = "debugLogging"

    /// TEMPORARY: defaults to **on** while the on-device placement bug is being chased. There
    /// is no route to Settings from the home window, so a tester cannot switch this on before
    /// entering the immersive space — which is exactly where the interesting logging happens.
    /// Flip the fallback back to `false` once that is closed (or give HomeView a Settings
    /// button, which is the better fix).
    ///
    /// Read fresh each time rather than cached: `UserDefaults` keeps this in memory, the
    /// `@autoclosure` below already avoids the expensive half (building the string), and a
    /// cache here would need invalidating from the settings toggle — a staleness bug waiting
    /// to happen in exchange for saving a dictionary lookup.
    static var isDebugEnabled: Bool {
        (UserDefaults.standard.object(forKey: debugLoggingKey) as? Bool) ?? true
    }

    private static let subsystem = Bundle.main.bundleIdentifier ?? "juanbuildstech.SPAI.ja"

    private static let loggers: [Category: Logger] = Dictionary(
        uniqueKeysWithValues: Category.allCases.map {
            ($0, Logger(subsystem: subsystem, category: $0.rawValue))
        }
    )

    private static func logger(_ category: Category) -> Logger {
        loggers[category] ?? Logger(subsystem: subsystem, category: category.rawValue)
    }

    /// Per-frame and per-detection detail. Silent unless debug logging is on.
    ///
    /// The `@autoclosure` earns its keep here: several call sites interpolate detection counts
    /// or transforms on every frame, and formatting those strings only to discard them is real
    /// work in a hot path.
    static func debug(_ category: Category, _ message: @autoclosure () -> String) {
        guard isDebugEnabled else { return }
        // The local is not redundant: os_log's own interpolation takes an *escaping*
        // autoclosure, which a non-escaping one cannot be passed into. Laziness is
        // preserved either way — nothing is built until past the guard above.
        //
        // `privacy: .public` is required, not decorative: os_log redacts interpolated
        // non-literal values as `<private>` by default, which would reduce every one of
        // these messages to the word "<private>" on device.
        let text = message()
        logger(category).debug("\(text, privacy: .public)")
    }

    /// Milestones worth seeing when following a session — a model loading, tracking starting,
    /// a calibration landing. Gated, because in aggregate they are still noise.
    static func info(_ category: Category, _ message: @autoclosure () -> String) {
        guard isDebugEnabled else { return }
        let text = message()
        logger(category).info("\(text, privacy: .public)")
    }

    /// Something failed or fell back. Always emitted, whatever the toggle says.
    static func error(_ category: Category, _ message: @autoclosure () -> String) {
        let text = message()
        logger(category).error("\(text, privacy: .public)")
    }
}
