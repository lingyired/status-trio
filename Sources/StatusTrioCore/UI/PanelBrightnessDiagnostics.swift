import Foundation
import os

/// Opt-in, DEBUG-only diagnostics for the panel brightness slider (#331).
///
/// Disabled by default and compiled to a no-op in Release, so it adds no
/// runtime logging, timers, or polling there. Enable it from a debugger or an
/// isolated diagnostic run by setting `PanelBrightnessDiagnostics.isEnabled =
/// true`, then reproduce the drag; every line carries a single monotonic
/// timestamp (`ProcessInfo.systemUptime`) so slider events can be ordered
/// without comparing wall clocks.
enum PanelBrightnessDiagnostics {
    /// Toggle from a debugger (`expression -- PanelBrightnessDiagnostics.isEnabled = true`)
    /// before reproducing. Stays `false` in normal use.
    nonisolated(unsafe) static var isEnabled = false
}

#if DEBUG

extension PanelBrightnessDiagnostics {
    private static let logger = Logger(
        subsystem: "com.lingsmbp.StatusTrio",
        category: "BrightnessDiagnostics"
    )

    static func event(_ layer: String, _ gestureID: String, _ message: String) {
        guard isEnabled else { return }
        let timestamp = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        logger.debug(
            "t=\(timestamp, privacy: .public) [\(layer, privacy: .public)] [\(gestureID, privacy: .public)] \(message, privacy: .public)"
        )
    }
}

#else

extension PanelBrightnessDiagnostics {
    @inline(__always)
    static func event(_ layer: String, _ gestureID: String, _ message: String) {}
}

#endif
