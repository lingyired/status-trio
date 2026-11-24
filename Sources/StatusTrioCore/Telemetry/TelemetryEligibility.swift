struct TelemetryEligibilityContext: Sendable {
    let bundleIdentifier: String?
    let productionMarker: Bool
    let isDebugBuild: Bool
    let channel: DistributionChannel

    init(
        bundleIdentifier: String?,
        productionMarker: Bool,
        isDebugBuild: Bool,
        channel: DistributionChannel = .current
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.productionMarker = productionMarker
        self.isDebugBuild = isDebugBuild
        self.channel = channel
    }
}

enum TelemetryEligibility {
    static let productionBundleIdentifier = "com.lingsmbp.StatusTrio"

    static func isEligible(_ context: TelemetryEligibilityContext) -> Bool {
        context.channel == .direct
            && context.bundleIdentifier == productionBundleIdentifier
            && context.productionMarker
            && !context.isDebugBuild
    }
}
