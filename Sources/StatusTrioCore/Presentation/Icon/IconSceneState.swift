struct IconSceneState: Equatable, Hashable, Sendable {
    let outerRing: OuterRingState?
    let center: CenterState?
    let footer: FooterState?

    init(
        outerRing: OuterRingState? = nil,
        center: CenterState? = nil,
        footer: FooterState? = nil
    ) {
        self.outerRing = outerRing
        self.center = center
        self.footer = footer
    }
}

extension IconSceneState {
    /// Every colour role the scene draws with, in draw order. The renderer
    /// resolves each role against the menu bar appearance, so this list is the
    /// single source of truth for whether the artwork needs more than one colour.
    var colorRoles: [IconColorRole] {
        var roles: [IconColorRole] = []
        if let outerRing {
            roles.append(contentsOf: outerRing.segments.map(\.color))
            switch outerRing.accessory {
            case let .symbol(symbol): roles.append(symbol.color)
            case let .text(text): roles.append(text.color)
            case nil: break
            }
        }
        switch center {
        case let .symbol(symbol): roles.append(symbol.color)
        case let .text(text): roles.append(text.color)
        case nil: break
        }
        switch footer {
        case let .dots(dots): roles.append(dots.color)
        case let .arc(arc): roles.append(arc.color)
        case nil: break
        }
        return roles
    }

    /// `true` when the scene draws with the appearance's own label colour alone:
    /// every role is `.primary` or `.inactive`, and no chroma status colour
    /// (`critical`, `lowPower`, `powered`, `bluetooth`) is present.
    ///
    /// The menu bar uses this to hand such a scene to the system as a template
    /// image, which the system re-tints per Space in real time. A scene with any
    /// status colour stays a custom multi-colour raster because the system cannot
    /// re-tint it.
    var usesOnlyMonochromeRoles: Bool {
        chromaticRegions.isEmpty
    }

    /// The primitives the menu bar can hand to the system as a template image:
    /// everything that never carries a status colour, plus the primitives whose
    /// role resolves to the label colour.
    var templateRegions: IconSceneRegion {
        IconSceneRegion.all.subtracting(chromaticRegions)
    }

    /// The primitives that need a custom raster because they carry a status
    /// colour, or because the charging effect animates them.
    var chromaticRegions: IconSceneRegion {
        var regions: IconSceneRegion = []
        if let ring = outerRing {
            // The charging effect re-colours the ring fill and paints a highlight
            // derived from it, and it scales and tints the bolt when the heartbeat
            // is on. Each of those has to ride the animated overlay even when its
            // role alone would be the label colour. The percentage indicator is
            // not animated, so it stays with the template and keeps re-tinting.
            let hasEffect = ring.effect != nil
            if hasEffect || Self.isChromatic(ring.segments.first?.color) {
                regions.insert(.ringFill)
            }
            if hasEffect { regions.insert(.ringEffect) }
            if ring.effect?.pulsesAccessory == true || Self.isChromatic(ring.accessory?.colorRole) {
                regions.insert(.ringAccessory)
            }
        }
        if Self.isChromatic(center?.colorRole) { regions.insert(.center) }
        if Self.isChromatic(footer?.colorRole) { regions.insert(.footerFill) }
        return regions.intersection(IconSceneRegion.all)
    }

    private static func isChromatic(_ role: IconColorRole?) -> Bool {
        guard let role else { return false }
        return role != .primary && role != .inactive
    }
}

extension RingAccessoryState {
    var colorRole: IconColorRole {
        switch self {
        case let .symbol(symbol): symbol.color
        case let .text(text): text.color
        }
    }
}

extension CenterState {
    var colorRole: IconColorRole {
        switch self {
        case let .symbol(symbol): symbol.color
        case let .text(text): text.color
        }
    }
}

extension FooterState {
    var colorRole: IconColorRole {
        switch self {
        case let .dots(dots): dots.color
        case let .arc(arc): arc.color
        }
    }
}
