import Foundation

/// Abstraction for playing the system-gated volume-change tick. Shared consumers
/// (e.g. `SystemStatusStore`) depend on this boundary; the concrete
/// `VolumeFeedbackPlayer` (which reads a private beep preference) lives in the
/// Direct-only `VolumeFeedback.swift`.
@MainActor
protocol VolumeFeedbackPlaying: AnyObject {
    func playVolumeChangeFeedback()
}
