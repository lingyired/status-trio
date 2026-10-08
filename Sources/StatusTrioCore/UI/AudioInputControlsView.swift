import SwiftUI

/// Holds only the slider's temporary drag value; system readback remains authoritative.
struct AudioInputVolumeDraft {
    private(set) var value = 0.0
    private(set) var isEditing = false
    private var latestSystemScalar: Double?
    private var selectedDeviceIdentity: PanelAudioInputIdentity?

    mutating func receiveSystemScalar(_ scalar: Double?) {
        latestSystemScalar = scalar
        guard !isEditing else { return }
        value = Self.displayValue(for: scalar)
    }

    mutating func setEditing(_ editing: Bool) {
        isEditing = editing
        if !editing {
            value = Self.displayValue(for: latestSystemScalar)
        }
    }

    mutating func setSliderValue(
        _ newValue: Double,
        systemScalar: Double?,
        onScalarChange: (Double) -> Void
    ) {
        guard isEditing, newValue.isFinite,
              let systemScalar, systemScalar.isFinite,
              (0...1).contains(systemScalar) else { return }
        value = min(1, max(0, newValue))
        guard abs(value - Self.displayValue(for: systemScalar)) >= 0.0005 else { return }
        onScalarChange(value)
    }

    mutating func resetForDevice(_ scalar: Double?) {
        isEditing = false
        receiveSystemScalar(scalar)
    }

    mutating func receiveSystemState(
        deviceIdentity: PanelAudioInputIdentity?,
        scalar: Double?
    ) {
        let deviceChanged = selectedDeviceIdentity != deviceIdentity
        selectedDeviceIdentity = deviceIdentity
        if deviceChanged {
            resetForDevice(scalar)
        } else {
            receiveSystemScalar(scalar)
        }
    }

    func accessibilityValue(systemScalar: Double?, locale: Locale) -> String {
        guard let systemScalar, systemScalar.isFinite, (0...1).contains(systemScalar) else {
            return "—"
        }
        let displayedValue = isEditing ? value : systemScalar
        return displayedValue.formatted(
            .percent.precision(.fractionLength(0)).locale(locale)
        )
    }

    private static func displayValue(for scalar: Double?) -> Double {
        guard let scalar, scalar.isFinite, (0...1).contains(scalar) else { return 0 }
        return scalar
    }
}

struct AudioInputControlsView: View {
    @EnvironmentObject private var localization: Localization

    let state: AudioInputPanelState
    let actions: StatusPanelActions
    let onOpenSoundSettings: () -> Void

    @State private var volumeDraft = AudioInputVolumeDraft()

    private var sliderAccessibilityValue: String {
        volumeDraft.accessibilityValue(
            systemScalar: state.scalar,
            locale: localization.resolvedLanguage.locale
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            controls
            deviceList

            if let error = state.errorText {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityElement(children: .combine)
            } else if state.isBusy {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    Text(localization.string(.audioInputRefreshing))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            volumeDraft.receiveSystemState(
                deviceIdentity: state.selectedDeviceIdentity,
                scalar: state.scalar
            )
        }
        .onChange(of: state.selectedDeviceIdentity) { _, identity in
            volumeDraft.receiveSystemState(deviceIdentity: identity, scalar: state.scalar)
        }
        .onChange(of: state.scalar) { _, scalar in
            volumeDraft.receiveSystemScalar(scalar)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(state.usageText == nil ? Color.secondary : Color.white)
                .frame(width: 24, height: 24)
                .background {
                    Capsule()
                        .fill(state.usageText == nil ? Color.clear : Color.orange)
                        .frame(width: 32, height: 26)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.summary.title)
                    .font(.headline)
                    .foregroundStyle(state.usageText == nil ? Color.primary : Color.yellow)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(state.summary.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(state.summary.subtitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onOpenSoundSettings) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localization.string(.audioInputOpenSettings))
            .accessibilityLabel(localization.string(.audioInputOpenSettings))
            .frame(width: 24, height: 24)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(action: { actions.toggleInputMute() }) {
                HStack(spacing: 6) {
                    muteIcon
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(state.muteTint.color())
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)

                    if state.muteState == .partial {
                        Text(localization.string(.audioInputPartial))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!state.canMute)
            .help(state.muteHelp)
            .accessibilityLabel(state.muteHelp)
            .accessibilityValue(
                state.muteState == .partial ? localization.string(.audioInputPartial) : ""
            )
            .accessibilityHint(
                state.canMute ? "" : localization.string(.audioInputMuteUnavailable)
            )

            ZStack {
                Slider(
                    value: sliderValue,
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing { volumeDraft.receiveSystemScalar(state.scalar) }
                        volumeDraft.setEditing(editing)
                    }
                )
                .tint(state.muteState == .muted ? Color.secondary : Color.accentColor)
                .disabled(!state.canAdjust)
                .help(state.canAdjust
                    ? localization.string(.audioInputVolume)
                    : localization.string(.audioInputVolumeUnavailable))
                .accessibilityLabel(state.sliderLabel)
                .accessibilityValue(sliderAccessibilityValue)
                .accessibilityHint(
                    state.canAdjust ? "" : localization.string(.audioInputVolumeUnavailable)
                )

                if state.scalar == nil {
                    Text("—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .background(.background)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)

            Text(state.percentageText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 34, alignment: .trailing)
                .accessibilityHidden(true)

            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var muteIcon: some View {
        if state.muteState == .muted {
            Image(systemName: "mic.slash.fill")
        } else if state.muteState == .partial {
            Image(systemName: "mic.fill")
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                }
        } else {
            Image(systemName: state.muteSymbol)
        }
    }

    @ViewBuilder
    private var deviceList: some View {
        if state.showsDeviceList {
            Divider()
                .padding(.top, 2)

            VStack(spacing: 2) {
                ForEach(state.rows) { row in
                    Button {
                        guard !row.selected else { return }
                        actions.selectInput(row.key)
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(row.selected ? Color.accentColor : Color.secondary.opacity(0.14))
                                Image(systemName: row.selected ? "mic.fill" : "mic")
                                    .foregroundStyle(row.selected ? Color.white : Color.secondary)
                            }
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)

                            Text(row.name)
                                .font(.body.weight(row.selected ? .semibold : .regular))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!row.enabled)
                    .help(row.helpText)
                    .accessibilityLabel(row.accessibilityLabel)
                    .accessibilityHint(row.selected ? "" : row.helpText)
                }
            }
        } else {
            Label(localization.string(.audioInputNoDevices), systemImage: "mic.slash")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { state.scalar == nil ? 0.5 : volumeDraft.value },
            set: { newValue in
                volumeDraft.setSliderValue(newValue, systemScalar: state.scalar) {
                    actions.setInputScalar($0)
                }
            }
        )
    }
}
