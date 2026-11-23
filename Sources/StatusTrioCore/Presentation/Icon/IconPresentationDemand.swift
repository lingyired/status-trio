import Foundation

/// The live-source demand implied by one resolved icon scene.
///
/// It is deliberately independent from `IconSceneState`: two bindings can draw
/// identical pixels while needing different watches or metric sampling, so the
/// icon image must not be the trigger that starts or stops a source.
struct IconPresentationDemand: Equatable, Sendable {
    /// Slot bindings the scene actually drew, including a fallback that is on
    /// screen because the primary source is unavailable.
    var selectedBindings: Set<IconContentBinding> = []
    /// Bindings the host must keep subscribed while the slot is visible. This
    /// includes an external primary even when its fallback currently draws, so
    /// the package can recover without the user reopening Settings.
    var subscribedBindings: Set<IconContentBinding> = []
    /// Dependencies of the bindings that actually resolved.
    var dependencies: IconContentDependencies = .init()

    var hardwareMetricIDs: Set<HardwareMetricID> {
        dependencies.requiresHardwareMonitor ? dependencies.hardwareMetricIDs : []
    }

    static let none = Self()
}
