struct SystemBatteryIconPlugin: IconContentPlugin {
    let descriptor = IconContentPluginDescriptor(id: "builtin.system-battery", presentations: [
        .init(id: "ring", slot: .outerRing, title: .iconDesignerSourceSystemBattery, isSelectable: true, summary: .iconDesignerBatterySummary),
        .init(id: "percentage", slot: .center, title: .iconDesignerSourceBatteryPercentage, isSelectable: true, summary: .iconDesignerBatterySummary)
    ])

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        let battery = context.inputs.system.snapshot.battery
        let sourceID = presentationID == "ring" ? RingSource.systemBattery.rawValue : CenterSource.systemBatteryPercentage.rawValue
        let availability = context.inputs.sources.result(for: sourceID,
            default: presentationID == "ring" || battery.isPresent ? .available(true) : .unavailable(.unavailable))
        if case let .unavailable(reason) = availability { return .unavailable(reason) }
        switch presentationID {
        case "ring":
            return .available(.outerRing(IconPresentationMapper.scene(inputs: context.inputs.system, configuration: context.legacy).outerRing))
        case "percentage":
            // Numeric centre modes share one size rule on main: the Wi-Fi Icon
            // Size scale, so switching between percentage/watts does not resize
            // the number. Use the same source the legacy mapper does.
            return .available(.center(battery.isPresent ? .text(IconTextState(text: "\(battery.percentage)", color: .primary,
                scale: context.legacy.connection.wifiScale)) : nil))
        default: return .unavailable(.unavailable)
        }
    }

    func dependencies(presentationID: String, context: IconContentDependencyContext) -> IconContentDependencies {
        return .init(samples: [.macBattery])
    }

    func capabilities(presentationID: String, context: IconContentDependencyContext) -> Set<IconDesignerBehaviorCapability> {
        return presentationID == "ring" ? [.systemBattery] : []
    }

}
