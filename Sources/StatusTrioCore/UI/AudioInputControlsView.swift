import SwiftUI

/// Holds an edit until the readback acknowledges that exact scalar request.
struct AudioInputVolumeDraft {
    private(set) var value = 0.0
    private(set) var isEditing = false
    private var latestSystemScalar: Double?
    private var lastSubmittedValue: Double?
    private var pendingRequestID: UUID?
    private var selectedDeviceIdentity: PanelAudioInputIdentity?

    mutating func receiveSystemScalar(_ scalar: Double?) {
        latestSystemScalar = scalar
        pendingRequestID = nil
        guard !isEditing else { return }
        value = Self.displayValue(for: scalar)
    }

    mutating func setEditing(_ editing: Bool) {
        isEditing = editing
        if !editing, pendingRequestID == nil {
            value = Self.displayValue(for: latestSystemScalar)
        }
    }

    mutating func setSliderValue(
        _ newValue: Double,
        systemScalar: Double?,
        onScalarChange: (Double, UUID) -> Void
    ) {
        guard isEditing, newValue.isFinite,
              let systemScalar, systemScalar.isFinite,
              (0...1).contains(systemScalar) else { return }
        value = min(1, max(0, newValue))
        let previousValue = pendingRequestID != nil ? lastSubmittedValue ?? systemScalar : systemScalar
        guard abs(value - previousValue) >= 0.0005 else { return }
        lastSubmittedValue = value
        let requestID = UUID()
        pendingRequestID = requestID
        onScalarChange(value, requestID)
    }

    mutating func resetForDevice(_ scalar: Double?) {
        isEditing = false
        receiveSystemScalar(scalar)
    }

    mutating func receiveSystemState(
        deviceIdentity: PanelAudioInputIdentity?,
        scalar: Double?,
        canAdjust: Bool = true,
        isBusy: Bool = false,
        hasError: Bool = false,
        completedScalarRequestID: UUID? = nil
    ) {
        let deviceChanged = selectedDeviceIdentity != deviceIdentity
        let hasReadableScalar = scalar.map { $0.isFinite && (0...1).contains($0) } ?? false
        selectedDeviceIdentity = deviceIdentity
        if deviceChanged || hasError || !hasReadableScalar || (!isBusy && !canAdjust) {
            resetForDevice(scalar)
        } else if pendingRequestID == nil || pendingRequestID == completedScalarRequestID {
            receiveSystemScalar(scalar)
        }
    }

    func accessibilityValue(systemScalar: Double?, locale: Locale) -> String {
        guard let systemScalar, systemScalar.isFinite, (0...1).contains(systemScalar) else {
            return "—"
        }
        let displayedValue = isEditing || pendingRequestID != nil ? value : systemScalar
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
    @State private var isDeviceListExpanded = false

    private var sliderAccessibilityValue: String {
        volumeDraft.accessibilityValue(
            systemScalar: state.scalar,
            locale: localization.resolvedLanguage.locale
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls
            deviceList

            if let error = state.errorText {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityElement(children: .combine)
            }
        }
        .onAppear {
            volumeDraft.resetForDevice(state.scalar)
            synchronizeDraft(state)
        }
        .onChange(of: state) { newState in
            synchronizeDraft(newState)
        }
    }

    private func synchronizeDraft(_ state: AudioInputPanelState) {
        volumeDraft.receiveSystemState(
            deviceIdentity: state.selectedDeviceIdentity,
            scalar: state.scalar,
            canAdjust: state.canAdjust,
            isBusy: state.isBusy,
            hasError: state.errorText != nil,
            completedScalarRequestID: state.completedScalarRequestID
        )
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: { actions.toggleInputMute() }) {
                HStack(alignment: .center, spacing: 6) {
                    muteIcon
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(state.muteTint.color())
                        .frame(
                            width: PanelSummaryActionMetrics.hitTarget,
                            height: PanelSummaryActionMetrics.hitTarget
                        )
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

            Text(sliderAccessibilityValue)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 34, alignment: .trailing)
                .accessibilityHidden(true)

            Button(action: onOpenSoundSettings) {
                PanelActionGlyph(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .opacity(state.isBusy ? 0 : 1)
            }
            .buttonStyle(.plain)
            .overlay {
                if state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .help(localization.string(.audioInputOpenSettings))
            .accessibilityLabel(localization.string(.audioInputOpenSettings))
            .accessibilityValue(state.isBusy ? localization.string(.audioInputRefreshing) : "")
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
                ForEach(state.visibleRows(expanded: isDeviceListExpanded)) { row in
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

                            if row.selected, let usageText = state.usageText {
                                Text(usageText)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!row.enabled)
                    .help(row.helpText)
                    .accessibilityLabel(row.accessibilityLabel)
                    .accessibilityValue(row.selected ? state.usageText ?? "" : "")
                    .accessibilityHint(row.selected ? "" : row.helpText)
                }

                if state.hasHiddenRows {
                    DeviceListExpansionButton(
                        isExpanded: $isDeviceListExpanded,
                        expandLabel: state.expandLabel,
                        collapseLabel: state.collapseLabel
                    )
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
                volumeDraft.setSliderValue(newValue, systemScalar: state.scalar) { value, requestID in
                    actions.setInputScalar(value, requestID: requestID)
                }
            }
        )
    }
}
