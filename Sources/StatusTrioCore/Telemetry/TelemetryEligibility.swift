struct TelemetryEligibilityContext: Sendable {
    let bundleIdentifier: String?
    let productionMarker: Bool
    let isDebugBuild: Bool
}

enum TelemetryEligibility {
    static let productionBundleIdentifier = "com.lingsmbp.StatusTrio"

    static func isEligible(_ context: TelemetryEligibilityContext) -> Bool {
        context.bundleIdentifier == productionBundleIdentifier
            && context.productionMarker
            && !context.isDebugBuild
    }
}
