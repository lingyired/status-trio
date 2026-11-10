import Foundation

enum IconPaletteResolver {
    static func resolve(role: IconColorRole, style: SlotColorStyle) -> IconColorRole {
        let semanticRole = role.semanticRole
        switch style {
        case .automatic:
            return role
        case let .fixed(rawColor):
            let color = rawColor.normalized()
            guard semanticRole == .inactive else { return .custom(color) }
            return .custom(IconRGBA(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: color.alpha * IconColorRole.inactiveTrackOpacity
            ))
        case let .semanticOverrides(colors):
            guard let semanticRole, let color = colors[semanticRole] else { return role }
            return .custom(color.normalized())
        }
    }

    static func apply(
        _ scene: IconSceneState,
        appearance: IconAppearanceConfiguration,
        centerSource: CenterSource? = nil
    ) -> IconSceneState {
        let outerRing = scene.outerRing.map { ring in
            OuterRingState(
                segments: ring.segments.map {
                    RingSegmentState(progress: $0.progress, color: resolve(role: $0.color, style: appearance.outerRing.color), position: $0.position)
                },
                gap: ring.gap,
                layout: ring.layout,
                isPartial: ring.isPartial,
                accessory: ring.accessory.map { accessory in
                    switch accessory {
                    case let .symbol(symbol):
                        .symbol(IconSymbolState(source: symbol.source, color: resolve(role: symbol.color, style: appearance.outerRing.color), scale: symbol.scale))
                    case let .text(text):
                        .text(IconTextState(text: text.text, color: resolve(role: text.color, style: appearance.outerRing.color), scale: text.scale))
                    }
                },
                effect: ring.effect,
                strokeScale: appearance.outerRing.strokeScale,
                inactiveColor: resolve(role: ring.inactiveColor, style: appearance.outerRing.color),
                // Appearance resolution must not reset the #205 gap-progress mode.
                gapProgressMode: ring.gapProgressMode
            )
        }
        let centerScaleFactor = appearance.center.symbolScale / CenterAppearance.classic.symbolScale
        let effectiveCenterScale = appearance.center.effectiveSymbolScale
        let normalizedPercentageScale = appearance.center.normalizedPercentageScale
        let normalizedSizePercentage = appearance.center.normalizedSizePercentage
        let center: CenterState? = scene.center.map { state in
            switch state {
            case let .symbol(symbol):
                let normalizedScale = centerSource == .network
                    ? normalizedPercentageScale.map { $0 * CenterPercentageScaleCalibration.wifiScaleForCommonPercentageSize }
                    : nil
                return .symbol(IconSymbolState(
                    source: symbol.source,
                    color: resolve(role: symbol.color, style: appearance.center.color),
                    scale: normalizedSizePercentage == nil
                        ? (normalizedScale ?? effectiveCenterScale ?? symbol.scale * centerScaleFactor)
                        : symbol.scale,
                    normalizedSizePercentage: normalizedSizePercentage
                ))
            case let .text(text):
                let normalizedScale = centerSource == .systemBatteryPercentage
                    ? normalizedPercentageScale.map { $0 * CenterPercentageScaleCalibration.percentageScaleForCommonSize }
                    : nil
                return .text(IconTextState(
                    text: text.text,
                    color: resolve(role: text.color, style: appearance.center.color),
                    scale: normalizedSizePercentage == nil
                        ? (normalizedScale ?? effectiveCenterScale ?? text.scale * centerScaleFactor)
                        : text.scale,
                    normalizedSizePercentage: normalizedSizePercentage
                ))
            }
        }
        let footer: FooterState? = scene.footer.map { state in
            switch state {
            case let .dots(dots):
                .dots(DotsState(count: dots.count, activeCount: dots.activeCount,
                                color: resolve(role: dots.color, style: appearance.footer.color),
                                strokeScale: appearance.footer.strokeScale,
                                inactiveColor: resolve(role: dots.inactiveColor, style: appearance.footer.color)))
            case let .arc(arc):
                .arc(ArcState(progress: arc.progress, color: resolve(role: arc.color, style: appearance.footer.color),
                              strokeScale: appearance.footer.strokeScale,
                              inactiveColor: resolve(role: arc.inactiveColor, style: appearance.footer.color)))
            }
        }
        // Carry the scene-level payloads through appearance resolution: they are
        // not slot roles, and dropping them loses the #275 Bluetooth colour and
        // the battery status palette on the resolved scene.
        return IconSceneState(
            outerRing: outerRing,
            center: center,
            footer: footer,
            statusColors: scene.statusColors,
            bluetoothIconColor: scene.bluetoothIconColor
        )
    }
}

private extension IconColorRole {
    var semanticRole: IconSemanticColorRole? {
        switch self {
        case .primary: .primary
        case .inactive: .inactive
        case .critical: .critical
        case .lowPower: .lowPower
        case .powered: .powered
        case .bluetooth: .bluetooth
        case .bluetoothIcon: .bluetooth
        case .highPower: .powered
        case .custom: nil
        }
    }
}
