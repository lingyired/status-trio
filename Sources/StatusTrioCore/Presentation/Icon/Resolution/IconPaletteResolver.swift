import Foundation

enum IconPaletteResolver {
    static func resolve(role: IconColorRole, style: SlotColorStyle) -> IconColorRole {
        let semanticRole = role.semanticRole
        switch style {
        case .automatic:
            return role
        case let .fixed(color):
            return .custom(color.normalized())
        case let .semanticOverrides(colors):
            guard let semanticRole, let color = colors[semanticRole] else { return role }
            return .custom(color.normalized())
        }
    }

    static func apply(_ scene: IconSceneState, appearance: IconAppearanceConfiguration) -> IconSceneState {
        let outerRing = scene.outerRing.map { ring in
            OuterRingState(
                segments: ring.segments.map {
                    RingSegmentState(progress: $0.progress, color: resolve(role: $0.color, style: appearance.outerRing.color))
                },
                gap: ring.gap,
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
                inactiveColor: resolve(role: ring.inactiveColor, style: appearance.outerRing.color)
            )
        }
        let centerScaleFactor = appearance.center.symbolScale / CenterAppearance.classic.symbolScale
        let center: CenterState? = scene.center.map { state in
            switch state {
            case let .symbol(symbol):
                .symbol(IconSymbolState(source: symbol.source, color: resolve(role: symbol.color, style: appearance.center.color), scale: symbol.scale * centerScaleFactor))
            case let .text(text):
                .text(IconTextState(text: text.text, color: resolve(role: text.color, style: appearance.center.color), scale: text.scale * centerScaleFactor))
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
        return IconSceneState(outerRing: outerRing, center: center, footer: footer)
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
        case .custom: nil
        }
    }
}
