import AppKit
import SwiftUI

struct IconSizePreview: View {
    let size: Double
    let options: BatteryIconOptions

    var body: some View {
        Image(nsImage: StatusIconRenderer.image(
            scene: IconPreviewScene.make(
                status: .placeholder,
                configuration: IconPresentationConfiguration(
                    battery: options,
                    connection: .standard,
                    volume: .standard,
                    bluetooth: .standard
                )
            ),
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2
        ) ?? NSImage(size: NSSize(width: size, height: size)))
        .frame(width: CGFloat(SettingsStore.iconSizeRange.upperBound))
        .accessibilityHidden(true)
    }
}
