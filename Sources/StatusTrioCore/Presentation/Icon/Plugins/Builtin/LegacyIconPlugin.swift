struct LegacyIconPlugin: IconContentPlugin {
    let descriptor = IconContentPluginDescriptor(id: "builtin.legacy", presentations: [
        .init(id: "ring", slot: .outerRing, title: .iconDesignerSourceLegacy, isSelectable: false),
        .init(id: "center", slot: .center, title: .iconDesignerSourceLegacy, isSelectable: false)
    ])

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        let scene = IconPresentationMapper.scene(inputs: context.inputs.system, configuration: context.legacy)
        switch presentationID {
        case "ring": return .available(.outerRing(scene.outerRing))
        case "center": return .available(.center(scene.center))
        default: return .unavailable(.unavailable)
        }
    }

    func dependencies(presentationID: String, context: IconContentDependencyContext) -> IconContentDependencies {
        return .init()
    }

    func capabilities(presentationID: String, context: IconContentDependencyContext) -> Set<IconDesignerBehaviorCapability> {
        return presentationID == "ring" ? [.systemBattery] : [.legacyBatteryPercentageInCenter, .networkRepresentation, .bluetoothOutputAppearance]
    }

}
