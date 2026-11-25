import SwiftUI

/// Row shown in place of the volume/input slider when no audio device is
/// available (#378).
///
/// It mirrors the device-list empty state (icon + secondary text) so the two
/// surfaces read the same, but it fixes the row height to the normal control
/// row so the panel does not jump when a device disappears or comes back.
struct PanelAudioEmptyDevicesHint: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.body)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}
