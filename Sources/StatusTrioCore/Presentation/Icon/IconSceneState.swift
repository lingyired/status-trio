struct IconSceneState: Equatable, Hashable, Sendable {
    let outerRing: OuterRingState?
    let center: CenterState?
    let footer: FooterState?
    /// The per-role colour overrides carried with the scene so every copy — the
    /// render caches, the Dock key, the menu-bar overlay — resolves the same
    /// answer and a colour change invalidates the cached raster. `.standard`
    /// keeps the system semantic colours.
    let statusColors: BatteryStatusColors
    /// The middle Bluetooth glyph colour (#275). It rides the scene so both
    /// surfaces and every render cache agree on the same colour.
    let bluetoothIconColor: BluetoothIconColorSelection
    /// Which quantity the footer reports. It rides the scene so
    /// `isVolumeValueChange` can tell a genuine volume change from a Wi-Fi or
    /// battery update, and so a source change invalidates the Dock cache.
    let bottomIndicatorSource: BottomIndicatorSource

    init(
        outerRing: OuterRingState? = nil,
        center: CenterState? = nil,
        footer: FooterState? = nil,
        statusColors: BatteryStatusColors = .standard,
        bluetoothIconColor: BluetoothIconColorSelection = .default,
        bottomIndicatorSource: BottomIndicatorSource = .volume
    ) {
        self.outerRing = outerRing
        self.center = center
        self.footer = footer
        self.statusColors = statusColors
        self.bluetoothIconColor = bluetoothIconColor
        self.bottomIndicatorSource = bottomIndicatorSource
    }
}

extension IconSceneState {
    /// Removes the shared charging-effect metadata for a surface whose own
    /// switch is off. Every other part of the scene is preserved.
    func withChargingEffectEnabled(_ enabled: Bool) -> IconSceneState {
        guard !enabled, let ring = outerRing, ring.effect != nil else { return self }
        return IconSceneState(
            outerRing: OuterRingState(
                segments: ring.segments,
                gap: ring.gap,
                accessory: ring.accessory,
                effect: nil,
                strokeScale: ring.strokeScale,
                gapProgressMode: ring.gapProgressMode
            ),
            center: center,
            footer: footer,
            statusColors: statusColors,
            bluetoothIconColor: bluetoothIconColor,
            bottomIndicatorSource: bottomIndicatorSource
        )
    }

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

extension IconSceneState {
    /// Tells a continuous volume *value* change apart from every other scene
    /// change. The Dock uses this to coalesce continuous volume adjustment
    /// without delaying settings or non-volume scene updates.
    ///
    /// It is a value change only when the source is volume on both scenes, the
    /// ring, centre and per-role colours are untouched, and the footer kept its
    /// kind, colour and stroke: a dots↔arc switch, a stroke change, a colour
    /// change, a source switch, or any ring/centre change is a settings or
    /// device change and stays on the immediate path. A Wi-Fi or battery footer
    /// update is never a volume change, so it must not be rate-limited as one.
    func isVolumeValueChange(from previous: IconSceneState) -> Bool {
        guard bottomIndicatorSource == .volume,
              previous.bottomIndicatorSource == .volume,
              outerRing == previous.outerRing,
              center == previous.center,
              statusColors == previous.statusColors,
              footer != previous.footer else {
            return false
        }
        switch (previous.footer, footer) {
        case let (.some(.dots(old)), .some(.dots(new))):
            return old.count == new.count
                && old.color == new.color
                && old.strokeScale == new.strokeScale
        case let (.some(.arc(old)), .some(.arc(new))):
            return old.color == new.color
                && old.strokeScale == new.strokeScale
        default:
            return false
        }
    }
}
