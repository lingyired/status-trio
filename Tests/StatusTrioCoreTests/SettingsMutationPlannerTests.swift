import Foundation
import Testing
@testable import StatusTrioCore

@Suite("Settings mutation planner")
struct SettingsMutationPlannerTests {

    private func planner() -> SettingsPlanner {
        SettingsPlanner(registry: SettingsSemanticCatalog.makeRegistry())
    }

    @Test("Enabling a feature enables its parents and emits dependency mutations")
    func featureClosureEnablesDependencies() {
        let plan = planner().plan(enableFeature: "hardware.panel.gpu.temperature", snapshot: SettingsSnapshot())
        #expect(plan.isApplicable)
        let byID = Dictionary(uniqueKeysWithValues: plan.operations.map { ($0.preferenceID, $0) })
        #expect(byID["hardware.rings.enabled"]?.value == .bool(true))
        #expect(byID["icon.outerRing.source"]?.value == .string("hardwareMonitor"))
        #expect(byID["icon.outerRing.hardware.primaryMetric"]?.value == .string("gpuUsage"))
        #expect(byID["hardware.temperature.enabled"]?.value == .bool(true))
        // Parent-derived operations are marked as dependencies.
        #expect(byID["hardware.rings.enabled"]?.source == .dependency)
        #expect(byID["hardware.temperature.enabled"]?.source == .requested)
    }

    @Test("Planning an already-satisfied feature is a no-op")
    func alreadySatisfiedFeatureIsNoOp() {
        let snapshot = SettingsSnapshot(values: [
            "hardware.rings.enabled": .bool(true),
            "icon.outerRing.source": .string("hardwareMonitor"),
            "icon.outerRing.hardware.layout": .string("single"),
            "icon.outerRing.hardware.primaryMetric": .string("gpuUsage"),
            "hardware.temperature.enabled": .bool(true),
        ])
        let plan = planner().plan(enableFeature: "hardware.panel.gpu.temperature", snapshot: snapshot)
        #expect(plan.operations.isEmpty)
        #expect(plan.isApplicable)
    }

    @Test("Dual-ring duplicate metric is resolved by swapping the other slot")
    func dualRingSwap() {
        let snapshot = SettingsSnapshot(values: [
            "icon.outerRing.source": .string("hardwareMonitor"),
            "icon.outerRing.hardware.layout": .string("dual"),
            "icon.outerRing.hardware.primaryMetric": .string("cpuUsage"),
            "icon.outerRing.hardware.secondaryMetric": .string("gpuUsage"),
        ])
        let plan = planner().plan(setPreference: "icon.outerRing.hardware.primaryMetric", to: .string("gpuUsage"), snapshot: snapshot)
        #expect(plan.isApplicable)
        let byID = Dictionary(uniqueKeysWithValues: plan.operations.map { ($0.preferenceID, $0) })
        #expect(byID["icon.outerRing.hardware.primaryMetric"]?.value == .string("gpuUsage"))
        #expect(byID["icon.outerRing.hardware.secondaryMetric"]?.value == .string("cpuUsage"))
        #expect(byID["icon.outerRing.hardware.secondaryMetric"]?.source == .constraint)
    }

    @Test("Removing the last ring slot is rejected")
    func minimumRingSlotRejected() {
        let snapshot = SettingsSnapshot(values: [
            "icon.outerRing.hardware.ringSlots": .array([.string("cpu")]),
        ])
        let plan = planner().plan(mutations: [
            SettingsMutationDescriptor(id: "icon.outerRing.hardware.ringSlots", operation: .remove, value: .string("cpu")),
        ], snapshot: snapshot)
        #expect(!plan.isApplicable)
        #expect(plan.errors.contains { $0.preferenceID == "icon.outerRing.hardware.ringSlots" })
    }

    @Test("Bold-text virtual toggle mirrors to both weight fields")
    func boldTextMirrors() {
        let plan = planner().plan(setPreference: "panel.appearance.boldText", to: .bool(false), snapshot: SettingsSnapshot())
        #expect(plan.isApplicable)
        let byID = Dictionary(uniqueKeysWithValues: plan.operations.map { ($0.preferenceID, $0) })
        #expect(byID["panel.appearance.boldText.titleWeight"]?.value == .bool(false))
        #expect(byID["panel.appearance.boldText.mediumWeight"]?.value == .bool(false))
        #expect(byID["panel.appearance.boldText.titleWeight"]?.source == .connected)
    }

    @Test("Type mismatch is rejected and makes the plan inapplicable")
    func invalidTypeRejected() {
        let plan = planner().plan(setPreference: "battery.thresholds.critical", to: .string("bad"), snapshot: SettingsSnapshot())
        #expect(!plan.isApplicable)
    }

    @Test("Out-of-range number is rejected")
    func rangeRejected() {
        let plan = planner().plan(setPreference: "general.iconSize", to: .number(100), snapshot: SettingsSnapshot())
        #expect(!plan.isApplicable)
        #expect(plan.errors.contains { $0.preferenceID == "general.iconSize" })
    }

    @Test("Planning is deterministic")
    func planningIsDeterministic() {
        let snapshot = SettingsSnapshot()
        let a = planner().plan(enableFeature: "hardware.panel.gpu.temperature", snapshot: snapshot)
        let b = planner().plan(enableFeature: "hardware.panel.gpu.temperature", snapshot: snapshot)
        #expect(a == b)
    }

    @Test("Setting the current value produces no operations")
    func idempotentWhenUnchanged() {
        let snapshot = SettingsSnapshot(values: ["panel.behavior.showOnHover": .bool(true)])
        let plan = planner().plan(setPreference: "panel.behavior.showOnHover", to: .bool(true), snapshot: snapshot)
        #expect(plan.operations.isEmpty)
    }
}
