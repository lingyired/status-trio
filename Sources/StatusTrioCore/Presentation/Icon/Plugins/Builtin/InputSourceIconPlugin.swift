struct InputSourceIconPlugin: IconContentPlugin {
    let descriptor = IconContentPluginDescriptor(id: "builtin.input-source", presentations: [
        .init(id: "center", slot: .center, title: .iconDesignerSourceInputSource, isSelectable: true, summary: .iconDesignerInputSourceSummary)
    ])

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        guard presentationID == "center", let input = context.inputs.system.inputSource else { return .unavailable(.unavailable) }
        return .available(.center(IconPresentationMapper.inputSourceCenterState(input, scale: context.legacy.connection.wifiScale)))
    }

    func dependencies(presentationID: String, context: IconContentDependencyContext) -> IconContentDependencies {
        return .init(samples: [.inputSource])
    }

    func capabilities(presentationID: String, context: IconContentDependencyContext) -> Set<IconDesignerBehaviorCapability> {
        return []
    }

}
