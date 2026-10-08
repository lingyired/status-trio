struct StatusBarRenderKey: Equatable {
    let scene: IconSceneState
    let iconSize: Double
    let backingScale: Double
    let appearanceName: String
    let phase: ChargingEffectPhase?
}

struct StatusBarRenderCache {
    private(set) var successfulKey: StatusBarRenderKey?

    func needsRender(_ key: StatusBarRenderKey) -> Bool {
        key != successfulKey
    }

    mutating func recordSuccessfulRender(_ key: StatusBarRenderKey) {
        successfulKey = key
    }

    mutating func reset() {
        successfulKey = nil
    }
}
