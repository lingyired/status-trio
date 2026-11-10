import Foundation

@MainActor
protocol BatteryMonitoring: AnyObject {
    var updates: AsyncStream<BatteryStatus> { get }
    func start()
    func stop()
    func refresh()
    func recover()
}

@MainActor
protocol WiFiMonitoring: AnyObject {
    var updates: AsyncStream<WiFiStatus> { get }
    func start()
    func stop()
    func refresh()
    func recover()
    @discardableResult
    func requestNameAccess() -> WiFiNameAccessRequestResult
    func setDetailsVisible(_ visible: Bool)
}

@MainActor
extension WiFiMonitoring {
    func setDetailsVisible(_ visible: Bool) {}
}

@MainActor
protocol NetworkConnectionMonitoring: AnyObject {
    var updates: AsyncStream<NetworkPathSnapshot> { get }
    func start()
    func stop()
    func recover()
}

@MainActor
protocol VPNMonitoring: AnyObject {
    var updates: AsyncStream<VPNStatus> { get }
    func start()
    func stop()
    func refresh()
    func recover()
}

@MainActor
protocol VolumeMonitoring: AnyObject {
    var updates: AsyncStream<VolumeStatus> { get }
    var betterDisplayCatalogUpdates: AsyncStream<BetterDisplayCatalogUpdate> { get }
    func start()
    func stop()
    func refresh()
    func recover()
    func setDetailsVisible(_ visible: Bool)
    func setDisplayAsleep(_ asleep: Bool)
    func topologyChanged()
    func setExternalVolumeConfigurations(
        _ configurations: [String: ExternalVolumeConfiguration]
    )
    func refreshBetterDisplayDevices()
}

@MainActor
protocol BrightnessMonitoring: AnyObject {
    var updates: AsyncStream<BrightnessStatus> { get }
    /// Latest actual backend observation for this display, independently of
    /// publications caused by other displays.
    func latestUpdateSequence(forDisplayID displayID: String) -> UInt64
    func start()
    func stop()
    func refresh()
    func recover()
    func setDetailsVisible(_ visible: Bool)
    func setDisplayAsleep(_ asleep: Bool)
    func topologyChanged()
    /// Select the backend allowed to drive one display, keyed by display UUID.
    func setBackend(_ backend: BrightnessBackend, forDisplayID displayID: String)
    func setExternalBrightnessConfigurations(
        _ configurations: [String: ExternalBrightnessConfiguration]
    )
    func setBrightness(_ scalar: Double, forDisplayID displayID: String)
    func finishBrightnessAdjustment(displayID: String)
}

@MainActor
extension BrightnessMonitoring {
    func latestUpdateSequence(forDisplayID displayID: String) -> UInt64 { 0 }
    func setDetailsVisible(_ visible: Bool) {}
    func setDisplayAsleep(_ asleep: Bool) {}
    func topologyChanged() {}
    func setBackend(_ backend: BrightnessBackend, forDisplayID displayID: String) {}
    func setExternalBrightnessConfigurations(
        _ configurations: [String: ExternalBrightnessConfiguration]
    ) {}
    func setBrightness(_ scalar: Double, forDisplayID displayID: String) {}
    func finishBrightnessAdjustment(displayID: String) {}
}

@MainActor
extension VolumeMonitoring {
    var betterDisplayCatalogUpdates: AsyncStream<BetterDisplayCatalogUpdate> {
        AsyncStream { $0.finish() }
    }

    func setDetailsVisible(_ visible: Bool) {}
    func setDisplayAsleep(_ asleep: Bool) {}
    func topologyChanged() {}
    func setExternalVolumeConfigurations(
        _ configurations: [String: ExternalVolumeConfiguration]
    ) {}
    func refreshBetterDisplayDevices() {}
}
