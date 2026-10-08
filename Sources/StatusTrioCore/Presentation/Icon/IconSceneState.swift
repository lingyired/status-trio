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
