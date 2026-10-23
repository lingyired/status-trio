struct SystemVolumeIconPlugin: IconContentPlugin {
    let descriptor = IconContentPluginDescriptor(id: "builtin.system-volume", presentations: [
        .init(id: "footer", slot: .footer, title: .iconDesignerSourceSystemVolume, isSelectable: true, summary: .iconDesignerVolumeSummary)
    ])

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        guard presentationID == "footer" else { return .unavailable(.unavailable) }
        if case let .unavailable(reason) = context.inputs.sources.result(for: FooterSource.systemVolume.rawValue, default: .available(true)) {
            return .unavailable(reason)
        }
        return .available(.footer(IconPresentationMapper.scene(inputs: context.inputs.system, configuration: context.legacy).footer))
    }

    func dependencies(presentationID: String, context: IconContentDependencyContext) -> IconContentDependencies {
        return .init(samples: [.systemVolume])
    }

    func capabilities(presentationID: String, context: IconContentDependencyContext) -> Set<IconDesignerBehaviorCapability> {
        return [.systemVolume]
    }

}
