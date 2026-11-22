import Foundation

struct IconContentBinding: Codable, Equatable, Hashable, Sendable {
    let pluginID: String
    let presentationID: String

    /// External manifests reject the reserved `builtin.` prefix, so the ID is a
    /// reliable owner marker.
    var isBuiltinSource: Bool { pluginID.hasPrefix("builtin.") }
    var isExternalSource: Bool { !isBuiltinSource }
}

struct IconContentPresentation: Equatable, Sendable {
    let id: String
    let slot: IconSlot
    /// Localized fallback for compiled-in presentations.
    let title: LocalizationKey
    let isSelectable: Bool
    var summary: LocalizationKey? = nil
    /// Manifest-provided title for an external presentation. `nil` keeps the
    /// localized `title`.
    var displayTitle: String? = nil
}

struct IconContentPluginDescriptor: Equatable, Sendable {
    let id: String
    let presentations: [IconContentPresentation]
}

struct IconContentOption: Equatable, Sendable {
    let binding: IconContentBinding
    let presentation: IconContentPresentation
}

enum IconContentPayload: Equatable, Sendable {
    case outerRing(OuterRingState?)
    case center(CenterState?)
    case footer(FooterState?)

    var slot: IconSlot {
        switch self {
        case .outerRing: .outerRing
        case .center: .center
        case .footer: .footer
        }
    }
}

struct IconContentContext: Sendable {
    let inputs: IconResolutionInputs
    let configuration: IconConfigurationV1
    let legacy: IconPresentationConfiguration
    let now: Date
    /// The host can ask for a warning representation even when the ordinary
    /// source is unavailable (for example Wi-Fi switched off).
    var isAlertOverride = false
    /// Which hardware-monitor metric the `.metric` bottom source draws. Only the
    /// footer hardware presentation reads it; other slots ignore it.
    var bottomIndicatorMetric: HardwareMonitorMetric = .cpuUsage
}

/// Compiled-in content reads a supplied snapshot. The host owns persistence,
/// monitoring, fallback selection, appearance and the actual drawing surfaces.
protocol IconContentPlugin: Sendable {
    var descriptor: IconContentPluginDescriptor { get }
    func dependencies(presentationID: String, context: IconContentDependencyContext) -> IconContentDependencies
    func capabilities(presentationID: String, context: IconContentDependencyContext) -> Set<IconDesignerBehaviorCapability>
    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload>
}

extension IconContentPlugin {
    func dependencies(presentationID: String, context: IconContentDependencyContext) -> IconContentDependencies { .init() }
    func capabilities(presentationID: String, context: IconContentDependencyContext) -> Set<IconDesignerBehaviorCapability> { [] }
}
