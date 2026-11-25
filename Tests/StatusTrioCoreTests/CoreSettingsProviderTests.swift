import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
@Suite("Core settings provider")
struct CoreSettingsProviderTests {

    private func makeStore() -> (SettingsStore, UserDefaults) {
        let suite = "CoreSettingsProviderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(
            defaults: defaults,
            systemChargeLimit: { nil },
            isDevelopmentBuild: true
        )
        return (store, defaults)
    }

    @Test("Boolean preference round-trips through the store")
    func booleanRoundTrip() {
        let (store, defaults) = makeStore()
        let provider = CoreSettingsProvider(store: store)
        provider.setValue(.bool(false), for: "panel.behavior.showOnHover")
        #expect(store.showsPanelOnHover == false)
        #expect(provider.value(for: "panel.behavior.showOnHover") == .bool(false))
    }

    @Test("Hardware ring layout writes the nested configuration")
    func hardwareRingLayout() {
        let (store, _) = makeStore()
        let provider = CoreSettingsProvider(store: store)
        provider.setValue(.string("dual"), for: "icon.outerRing.hardware.layout")
        #expect(store.hardwareRingConfiguration.layout == .dual)
        #expect(provider.value(for: "icon.outerRing.hardware.layout") == .string("dual"))
    }

    @Test("Ring slots use the domain setter")
    func ringSlots() {
        let (store, _) = makeStore()
        let provider = CoreSettingsProvider(store: store)
        provider.setValue(.array([.string("cpu"), .string("gpu")]), for: "icon.outerRing.hardware.ringSlots")
        #expect(store.enabledHardwareRingSlots == Set([.cpu, .gpu]))
    }

    @Test("Service applies a feature through the real store")
    func serviceAppliesFeature() throws {
        let (store, _) = makeStore()
        let service = SettingsServiceFactory.make(for: store)
        try service.apply(enableFeature: "hardware.panel.gpu.temperature")
        #expect(store.hardwareTemperatureMonitoringEnabled == true)
        #expect(store.outerRingContent == .hardwareMonitor)
        #expect(store.hardwareRingConfiguration.primaryMetric == .gpuUsage)
    }
}
