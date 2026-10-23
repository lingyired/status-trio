import Foundation

struct IconContentBinding: Equatable, Hashable, Sendable {
    let pluginID: String
    let presentationID: String
}

struct IconContentPresentation: Equatable, Sendable {
    let id: String
    let slot: IconSlot
    let title: LocalizationKey
    let isSelectable: Bool
    var summary: LocalizationKey? = nil
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
