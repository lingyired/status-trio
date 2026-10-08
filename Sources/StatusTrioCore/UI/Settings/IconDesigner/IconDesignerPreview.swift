import Foundation

/// Value-only lifecycle for preview animation. It owns no monitoring demand.
struct IconDesignerPreviewState: Equatable, Sendable {
    static let availableScenarios = IconPreviewScenario.allCases

    private(set) var playback = ChargingEffectPreviewPlayback()
    private(set) var isVisible = true
    private(set) var reduceMotion = false
    private(set) var scenario: IconPreviewScenario = .live

    mutating func start(at date: Date) {
        guard isVisible, !reduceMotion,
              scenario == .live || scenario == .batteryCharging else {
            playback.stop()
            return
        }
        playback.start(at: date)
    }

    mutating func setScenario(_ scenario: IconPreviewScenario) {
        self.scenario = scenario
        if scenario != .live && scenario != .batteryCharging { playback.stop() }
    }

    mutating func stop() {
        playback.stop()
    }

    mutating func setVisible(_ visible: Bool) {
        isVisible = visible
        if !visible { playback.stop() }
    }

    mutating func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
        if enabled { playback.stop() }
    }
}
