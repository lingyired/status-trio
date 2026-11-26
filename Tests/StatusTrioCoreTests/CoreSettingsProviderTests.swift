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

    @Test("Power info bar preference reaches the store, so a dev profile can enable it")
    func powerInfoBarRoundTrip() {
        let (store, _) = makeStore()
        let provider = CoreSettingsProvider(store: store)
        #expect(store.showsBatteryPowerInfoBar == false)
        provider.setValue(.bool(true), for: "battery.powerInfoBar.enabled")
        #expect(store.showsBatteryPowerInfoBar == true)
        #expect(provider.value(for: "battery.powerInfoBar.enabled") == .bool(true))
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

    @Test("Every core descriptor is handled by CoreSettingsProvider")
    func allCoreDescriptorsHandled() {
        let registry = SettingsSemanticCatalog.makeRegistry()
        let unhandled = registry.listPreferences()
            .filter { $0.provider == "core" && !CoreSettingsProvider.handledPreferenceIDs.contains($0.id) }
            .map(\.id)
        #expect(unhandled.isEmpty, "unhandled core descriptors: \(unhandled)")
        let unwritable = registry.listPreferences()
            .filter { $0.provider == "core" && ($0.accessPolicy?.developmentProfile ?? false) && !CoreSettingsProvider.handledPreferenceIDs.contains($0.id) }
            .map(\.id)
        #expect(unwritable.isEmpty, "dev-profile-writable but unhandled: \(unwritable)")
    }

    @Test("A newly mapped battery flag round-trips")
    func newlyMappedFlagRoundTrips() {
        let (store, _) = makeStore()
        let provider = CoreSettingsProvider(store: store)
        provider.setValue(.bool(false), for: "battery.charging.menuBarEffect")
        #expect(store.showsMenuBarChargingEffect == false)
        #expect(provider.value(for: "battery.charging.menuBarEffect") == .bool(false))
    }

    @Test("A battery marker enum round-trips")
    func markerEnumRoundTrips() {
        let (store, _) = makeStore()
        let provider = CoreSettingsProvider(store: store)
        provider.setValue(.string("bolt"), for: "battery.marker.charging")
        #expect(store.batteryChargingMarker == .bolt)
        #expect(provider.value(for: "battery.marker.charging") == .string("bolt"))
    }

}
