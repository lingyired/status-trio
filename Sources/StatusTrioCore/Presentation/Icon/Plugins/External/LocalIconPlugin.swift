import Foundation

/// Compiled adapter for one enabled local JSON package.
///
/// The manifest is fixed for the lifetime of this plugin value; readings live in
/// the shared value store and are replaced by the package feed. Resolving is
/// synchronous and side-effect free, like every other content plugin.
struct LocalIconPlugin: IconContentPlugin {
    let manifest: LocalIconPluginManifest
    let store: LocalIconPluginValueStore

    var descriptor: IconContentPluginDescriptor {
        IconContentPluginDescriptor(
            id: manifest.pluginID,
            presentations: manifest.presentations.map { presentation in
                IconContentPresentation(
                    id: presentation.id,
                    slot: presentation.slot.iconSlot,
                    title: .iconDesignerSourceNetwork,
                    isSelectable: true,
                    summary: nil,
                    displayTitle: manifest.title
                )
            }
        )
    }

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        guard let presentation = manifest.presentations.first(where: { $0.id == presentationID }),
              let value = store.value(
                pluginID: manifest.pluginID,
                presentationID: presentationID,
                now: context.now) else {
            return .unavailable(.temporarilyStale)
        }
        switch (presentation.slot, presentation.kind, value) {
        case let (.center, .text, .text(text)):
            return .available(.center(.text(IconTextState(
                text: text,
                color: .primary,
                scale: context.legacy.connection.wifiScale
            ))))
        case let (.outerRing, .fraction, .fraction(fraction)):
            return .available(.outerRing(OuterRingState(
                segments: [RingSegmentState(progress: fraction, color: .primary)],
                gap: .closed,
                strokeScale: context.legacy.battery.ringStrokeScale,
                inactiveColor: .inactive
            )))
        case let (.footer, .fraction, .fraction(fraction)):
            return .available(.footer(Self.footerState(fraction: fraction, legacy: context.legacy)))
        default:
            return .unavailable(.unavailable)
        }
    }

    private static func footerState(
        fraction: Double,
        legacy: IconPresentationConfiguration
    ) -> FooterState {
        let options = legacy.volume
        switch options.displayStyle {
        case .dots:
            return .dots(DotsState(
                count: 4,
                activeCount: Int((fraction * 4).rounded()),
                color: .primary,
                strokeScale: options.ringStrokeScale
            ))
        case .arc:
            return .arc(ArcState(
                progress: fraction,
                color: .primary,
                strokeScale: options.ringStrokeScale
            ))
        }
    }
}
