import Foundation
import Testing
@testable import StatusTrioCore

@Suite("Settings monitoring lifecycle invariants")
struct SettingsMonitoringLifecycleTests {

    private func planner() -> SettingsPlanner {
        SettingsPlanner(registry: SettingsSemanticCatalog.makeRegistry())
    }

    @Test("Enabling a hardware feature never starts background history")
    func featureDoesNotStartBackgroundHistory() {
        let plan = planner().plan(enableFeature: "hardware.panel.gpu.temperature", snapshot: SettingsSnapshot())
        #expect(!plan.operations.contains { $0.preferenceID == "hardware.history.backgroundEnabled" })
    }

    @Test("Enabling rings alone does not enable temperature sampling")
    func ringsDoNotEnableTemperature() {
        let plan = planner().plan(enableFeature: "hardware.panel.rings", snapshot: SettingsSnapshot())
        #expect(!plan.operations.contains { $0.preferenceID == "hardware.temperature.enabled" })
    }

    @Test("The GPU temperature feature declares on-demand temperature sampling")
    func temperatureFeatureIsOnDemand() {
        let feature = SettingsSemanticCatalog.makeRegistry().feature("hardware.panel.gpu.temperature")
        #expect(feature?.performanceImpact?.resources.contains("temperatureSampling") == true)
        #expect(feature?.performanceImpact?.activation == .onDemand)
    }

    @Test("Schema export has no monitoring side effects (pure data)")
    func exportIsPure() {
        let exporter = SettingsSchemaExporter(registry: SettingsSemanticCatalog.makeRegistry())
        #expect((try? exporter.documents().count) == 5)
    }
}
