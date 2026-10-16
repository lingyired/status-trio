/// One drawing primitive of the menu bar icon.
///
/// Splitting the scene by region is how the menu bar hands the monochrome
/// primitives to the system as a template image while the status colours stay
/// in a separate custom raster: the system re-tints template images for the
/// Space that is on top, including while a switch is being dragged, and a custom
/// multi-colour bitmap cannot follow (#112). The split holds because the
/// renderer paints the primitives in `allPrimitives` order, so every status
/// colour is drawn after the chrome it sits on and the raster above the template
/// reproduces the one-pass picture (`IconSceneRegionTests`).
struct IconSceneRegion: OptionSet, Hashable, Sendable {
    let rawValue: Int

    /// The battery ring's unfilled track. Always the appearance's label colour.
    static let ringTrack = IconSceneRegion(rawValue: 1 << 0)
    /// The battery ring's progress arc, which carries the battery's status colour.
    static let ringFill = IconSceneRegion(rawValue: 1 << 1)
    /// The charging effect's highlight, drawn over the ring.
    static let ringEffect = IconSceneRegion(rawValue: 1 << 2)
    /// The bolt, plug, or percentage drawn in the ring's top gap.
    static let ringAccessory = IconSceneRegion(rawValue: 1 << 3)
    /// The middle connection glyph or text.
    static let center = IconSceneRegion(rawValue: 1 << 4)
    /// The volume indicator's inactive track: hidden dots or the arc's base.
    static let footerTrack = IconSceneRegion(rawValue: 1 << 5)
    /// The volume indicator's active dots, or the arc's fill.
    static let footerFill = IconSceneRegion(rawValue: 1 << 6)

    /// Every primitive, listed in draw order.
    static let allPrimitives: [IconSceneRegion] = [
        .ringTrack, .ringFill, .ringEffect, .ringAccessory, .center, .footerTrack, .footerFill
    ]

    /// Every primitive.
    static let all: IconSceneRegion = allPrimitives.reduce(into: IconSceneRegion()) {
        $0.formUnion($1)
    }

    /// Primitives the renderer only ever draws with the appearance's label
    /// colour, so they can always be tinted by the system.
    static let alwaysMonochrome: IconSceneRegion = [.ringTrack, .footerTrack]
}
