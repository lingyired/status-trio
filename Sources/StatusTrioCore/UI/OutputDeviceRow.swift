import SwiftUI

struct OutputDeviceRow: View {
    @EnvironmentObject private var localization: Localization
    let device: AudioOutputDevice
    let onSelect: (AudioOutputDevice) -> Void

    var body: some View {
        Button {
            onSelect(device)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(device.isCurrent ? Color.accentColor : Color.secondary.opacity(0.14))

                    Image(systemName: deviceSymbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(device.isCurrent ? Color.white : Color.secondary)
                }
                .frame(width: 28, height: 28)
                // Center the badge in the popup's shared 24pt icon column.
                .frame(width: 24, height: 24)

                Text(displayName)
                    .font(.body.weight(device.isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let volume = device.volume, volume.isFinite {
                    Text(
                        volume.formatted(
                            .percent
                                .precision(.fractionLength(0))
                                .locale(localization.resolvedLanguage.locale)
                        )
                    )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
            device.isCurrent
                ? localization.string(.volumeOutputCurrent)
                : localization.format(.volumeOutputSwitchTo, displayName)
        )
        .accessibilityValue(device.isCurrent ? localization.string(.volumeOutputCurrent) : "")
    }

    private var displayName: String {
        device.name ?? localization.string(.volumeOutputUnknownDevice)
    }

    private var deviceSymbolName: String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods pro") {
            return "airpodspro"
        } else if name.contains("airpods max") {
            return "airpodsmax"
        } else if name.contains("airpods") {
            return "airpods"
        } else if name.contains("headphone") || name.contains("耳机") {
            return "headphones"
        } else if name.contains("display") || name.contains("monitor") || name.contains("显示器") || name.contains("hdmi") {
            return "display"
        } else if name.contains("tv") || name.contains("television") {
            return "tv"
        } else if name.contains("macbook") || name.contains("internal") || name.contains("内置") {
            return "laptopcomputer"
        }
        return device.isCurrent ? "hifispeaker.fill" : "hifispeaker"
    }
}
