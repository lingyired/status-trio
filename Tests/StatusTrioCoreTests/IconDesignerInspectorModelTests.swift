import Foundation
import Testing
@testable import StatusTrioCore

struct IconDesignerInspectorModelTests {
    @Test func removingFallbackInvalidatesEditingTargetImmediately() {
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery, fallback: .systemBattery)
        #expect(IconDesignerInspectorModel.effectiveTarget(.fallback, slot: .outerRing, configuration: configuration) == .fallback)
        configuration.composition.outerRing.fallback = nil
        #expect(IconDesignerInspectorModel.effectiveTarget(.fallback, slot: .outerRing, configuration: configuration) == .primary)
    }

    @Test func noContentAndUneditableContentHaveNoBehaviorCard() {
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.center = SlotSelection(primary: .none)
        #expect(IconDesignerInspectorModel.hasEditableBehavior(slot: .center, target: .primary, configuration: configuration, targetIsAudio: false) == false)
        configuration.composition.center = SlotSelection(primary: .inputSource)
        #expect(IconDesignerInspectorModel.hasEditableBehavior(slot: .center, target: .primary, configuration: configuration, targetIsAudio: false) == false)
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery, fallback: .systemBattery)
        #expect(IconDesignerInspectorModel.hasEditableBehavior(slot: .outerRing, target: .fallback, configuration: configuration, targetIsAudio: false))
    }

    @Test func summaryNamesResolvedSourceAndNotConfiguredPrimary() {
        let trace = SlotResolutionTrace(selectedSourceID: "systemBattery", role: .fallback, primaryFailure: .disconnected, reason: .fallback(.disconnected))
        #expect(IconDesignerInspectorModel.displayedSourceName(for: trace) == .iconDesignerSourceSystemBattery)
        #expect(IconDesignerInspectorModel.displayedSourceName(for: .empty) == .iconDesignerSourceNone)
        let overridden = SlotResolutionTrace(selectedSourceID: "network", role: .primary, primaryFailure: nil, reason: .overridden(.networkProblem))
        #expect(IconDesignerInspectorModel.displayedSourceName(for: overridden) == .iconDesignerSourceNetwork)
    }

    @MainActor @Test func disclosureAndElementSelectionAreOnlySessionState() {
        let session = IconDesignerPreviewSession()
        let samples = session.samples
        session.expandedFallbackSlots.insert(.outerRing)
        session.selectedSlot = .center
        #expect(session.expandedFallbackSlots.contains(.outerRing))
        #expect(session.expandedFallbackSlots.contains(.center) == false)
        session.expandedFallbackSlots.insert(.center)
        session.expandedFallbackSlots.remove(.outerRing)
        #expect(session.expandedFallbackSlots == [.center])
        #expect(session.samples == samples)
        #expect(session.mode == .live)
    }
}
