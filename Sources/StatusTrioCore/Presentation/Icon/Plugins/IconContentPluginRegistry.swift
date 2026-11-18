import Foundation

enum IconContentRegistryError: Error, Equatable {
    case emptyID
    case duplicatePlugin(String)
    case duplicatePresentation(String, String)
}

struct IconContentPluginRegistry: Sendable {
    private let plugins: [String: any IconContentPlugin]
    private let options: [IconContentOption]

    init(plugins: [any IconContentPlugin]) throws {
        var indexed: [String: any IconContentPlugin] = [:]
        var options: [IconContentOption] = []
        for plugin in plugins {
            let descriptor = plugin.descriptor
            guard !descriptor.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw IconContentRegistryError.emptyID
            }
            guard indexed[descriptor.id] == nil else { throw IconContentRegistryError.duplicatePlugin(descriptor.id) }
            var presentationIDs = Set<String>()
            for presentation in descriptor.presentations {
                guard !presentation.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw IconContentRegistryError.emptyID
                }
                guard presentationIDs.insert(presentation.id).inserted else {
                    throw IconContentRegistryError.duplicatePresentation(descriptor.id, presentation.id)
                }
                options.append(IconContentOption(
                    binding: IconContentBinding(pluginID: descriptor.id, presentationID: presentation.id),
                    presentation: presentation))
            }
            indexed[descriptor.id] = plugin
        }
        self.plugins = indexed
        self.options = options
    }

    func presentations(for slot: IconSlot) -> [IconContentOption] {
        options.filter { $0.presentation.slot == slot && $0.presentation.isSelectable }
    }

    func presentation(for binding: IconContentBinding) -> IconContentPresentation? {
        options.first { $0.binding == binding }?.presentation
    }

    func resolve(_ binding: IconContentBinding, for slot: IconSlot, context: IconContentContext) -> SourceResult<IconContentPayload> {
        guard let presentation = presentation(for: binding), presentation.slot == slot,
              let plugin = plugins[binding.pluginID] else { return .unavailable(.unavailable) }
        let result = plugin.resolve(presentationID: binding.presentationID, context: context)
        if case let .available(payload) = result, payload.slot != slot { return .unavailable(.unavailable) }
        return result
    }

    func dependencies(for binding: IconContentBinding, context: IconContentDependencyContext) -> IconContentDependencies {
        guard presentation(for: binding) != nil, let plugin = plugins[binding.pluginID] else { return .init() }
        return plugin.dependencies(presentationID: binding.presentationID, context: context)
    }

    func capabilities(for binding: IconContentBinding, context: IconContentDependencyContext) -> Set<IconDesignerBehaviorCapability> {
        guard presentation(for: binding) != nil, let plugin = plugins[binding.pluginID] else { return [] }
        return plugin.capabilities(presentationID: binding.presentationID, context: context)
    }

}
