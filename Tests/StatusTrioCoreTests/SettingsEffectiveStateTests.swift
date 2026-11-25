import Foundation
import Testing
@testable import StatusTrioCore

@Suite("Settings effective state")
struct SettingsEffectiveStateTests {

    private func evaluator(_ capabilities: [String: SettingsCapabilityDescriptor.Availability] = [:]) -> SettingsStateEvaluator {
        SettingsStateEvaluator(
            registry: SettingsSemanticCatalog.makeRegistry(),
            capabilities: SettingsCapabilitySnapshot(capabilities)
        )
    }

    @Test("Liquid Glass unavailable makes the background style unavailable")
    func liquidGlassUnavailable() {
        let state = evaluator(["ui.liquidGlass": .unavailable])
            .state(of: "panel.appearance.backgroundStyle", in: SettingsSnapshot(values: ["panel.appearance.backgroundStyle": .string("solid")]))
        #expect(state == .unavailable)
    }

    @Test("A configured, effective value is active")
    func activeValue() {
        let state = evaluator(["ui.liquidGlass": .available])
            .state(of: "panel.appearance.backgroundStyle", in: SettingsSnapshot(values: ["panel.appearance.backgroundStyle": .string("solid")]))
        #expect(state == .active)
    }

    @Test("Unset effective value is inactive")
    func unsetInactive() {
        let state = evaluator().state(of: "panel.behavior.showOnHover", in: SettingsSnapshot())
        #expect(state == .inactive)
    }

    @Test("Secondary metric is inactive unless hardware ring + dual layout")
    func secondaryMetricEffectiveGuards() {
        let value: [String: SettingsTransferValue] = ["icon.outerRing.hardware.secondaryMetric": .string("gpuUsage")]
        var snapshot = SettingsSnapshot(values: value.merging(["icon.outerRing.source": .string("systemBattery")]) { $1 })
        #expect(evaluator().state(of: "icon.outerRing.hardware.secondaryMetric", in: snapshot) == .inactive)
        snapshot = SettingsSnapshot(values: value.merging([
            "icon.outerRing.source": .string("hardwareMonitor"),
            "icon.outerRing.hardware.layout": .string("dual"),
        ]) { $1 })
        #expect(evaluator().state(of: "icon.outerRing.hardware.secondaryMetric", in: snapshot) == .active)
    }

    @Test("A false boolean is disabled")
    func booleanFalseDisabled() {
        let state = evaluator().state(of: "hardware.rings.enabled", in: SettingsSnapshot(values: ["hardware.rings.enabled": .bool(false)]))
        #expect(state == .disabled)
    }

    @Test("An unknown capability yields unknown, not unavailable")
    func unknownCapability() {
        var pref = SettingsPreferenceDescriptor(id: "test.needs.cap", title: "T", category: "test", type: .boolean)
        pref.availableWhen = .capability("cap.unknown")
        let registry = SettingsSemanticRegistry(preferences: [pref])
        let state = SettingsStateEvaluator(registry: registry, capabilities: SettingsCapabilitySnapshot())
            .state(of: "test.needs.cap", in: SettingsSnapshot(values: ["test.needs.cap": .bool(true)]))
        #expect(state == .unknown)
    }
}
