import SwiftUI

/// One paired-device row. The status panel's list and the detail page share it
/// so the two surfaces cannot drift, and a device the report carries no level
/// for simply draws no battery text.
///
/// The row is a pure function of its inputs: which action is in flight (or which
/// failure is on screen), and whether it is currently asking to confirm a
/// disconnect. The controller owns that confirmation, so the question cannot
/// outlive the panel that asked it.
///
/// A connected device is drawn the way Apple marks the control in use: its glyph
/// on a solid accent tile, its name in semibold. That is what says "connected" —
/// the row does not also spell it out or repeat it with a checkmark, which leaves
/// its trailing space to the battery level and to whatever an action is doing.
struct BluetoothDeviceRow: View {
    @EnvironmentObject private var localization: Localization
    let device: BluetoothDevice
    let batteryLevels: [String: BluetoothBatteryLevel]
    var mobileMetadataByDeviceID: [String: MobileBatterySnapshot] = [:]
    let actionState: BluetoothDeviceActionState?
    let isConfirmingDisconnect: Bool
    let onPerformAction: () -> Void
    let onRequestDisconnect: () -> Void
    let onCancelDisconnect: () -> Void

    var body: some View {
        let status = BluetoothDeviceActionPolicy.status(for: device, actionState: actionState)
        if isConfirmingDisconnect {
            HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
                badge
                name
                Spacer(minLength: 8)
                Text(localization.string(.bluetoothActionConfirmDisconnect))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(localization.string(.bluetoothActionDisconnect), action: onPerformAction)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                Button(localization.string(.bluetoothActionCancel), action: onCancelDisconnect)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .contain)
        } else if BluetoothDeviceActionPolicy.isActionable(device) {
            Button(action: { handleTap() }) {
                rowContent(status)
            }
            .buttonStyle(.plain)
            .disabled(isActionInFlight)
            .help(actionHelp)
            .accessibilityElement(children: .combine)
            // The word is gone from the row, so the state lives here instead: a
            // screen reader still hears whether the device is connected.
            .accessibilityValue(rowAccessibilityValue)
            .accessibilityHint(actionHelp)
        } else {
            // Read-only: a row a reading created has no paired connection to
            // make or break, so it is not a button and offers no action. The
            // level it carries is the whole of what it has to say.
            rowContent(status)
                .accessibilityElement(children: .combine)
                .accessibilityValue(rowAccessibilityValue)
        }
    }

    /// The row's content, whichever of the two layouts it uses. The interactive
    /// and read-only forms share it so they cannot drift.
    @ViewBuilder
    private func rowContent(_ status: BluetoothDeviceRowStatus) -> some View {
        switch BluetoothDevicePresentation.batteryLayout(
            for: device,
            batteryLevels: batteryLevels
        ) {
        case .inline:
            inlineContent(status)
        case .components:
            componentContent(status)
        }
    }

    /// The ordinary single-line row: the whole-device level, if any, sits at the
    /// trailing end of the name's line. A device with no component channels uses
    /// this unchanged, so ordinary Bluetooth devices cannot regress.
    private func inlineContent(_ status: BluetoothDeviceRowStatus) -> some View {
        HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
            badge
            VStack(alignment: .leading, spacing: 2) {
                name
                mobileDetails
            }

            Spacer(minLength: 8)

            batteryText

            trailingStatus(status)
        }
        .contentShape(Rectangle())
    }

    /// The two-line row a component-battery device gets. The badge owns the icon
    /// column and the whole height; the name and the component levels stack in the
    /// middle, the levels starting under the name rather than under the badge. The
    /// trailing status sits beside that stack, so — like the badge — it is centred
    /// on the whole row rather than pinned to the name's line. The level never
    /// competes with the name for width.
    private func componentContent(_ status: BluetoothDeviceRowStatus) -> some View {
        HStack(alignment: .center, spacing: BluetoothPanelMetrics.iconTextSpacing) {
            badge

            VStack(alignment: .leading, spacing: BluetoothPanelMetrics.componentBatteryLineSpacing) {
                name
                batteryText
                mobileDetails
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingStatus(status)
        }
        .contentShape(Rectangle())
        // Only this row gets the extra bottom room; inline rows and the list's
        // global spacing stay as compact as they are.
        .padding(.bottom, BluetoothPanelMetrics.componentRowBottomPadding)
    }

    /// The row's trailing edge. Only a state the row has to say in words (an action
    /// in flight, a failure) draws here; a plain connected device shows nothing,
    /// because the left badge's solid accent tile already says "connected" and a
    /// checkmark would only repeat it. Both layouts place this text at the trailing
    /// edge, vertically centred on the row: it belongs to the whole device, not to
    /// the name's line alone.
    @ViewBuilder
    private func trailingStatus(_ status: BluetoothDeviceRowStatus) -> some View {
        if status.drawsText {
            statusText(status)
        }
    }

    /// The device's glyph in the section's own icon column. A connected device is
    /// drawn the way Apple marks the control in use — a solid accent fill with a
    /// white glyph — rather than a faint accent tint under an accent glyph, which
    /// read as low-contrast whenever the accent was dark or pale.
    private var badge: some View {
        ZStack {
            Circle()
                .fill(
                    device.isConnected
                        ? Color.accentColor
                        : Color.secondary.opacity(0.14)
                )
            Image(systemName: BluetoothDeviceRowIcon.symbolName(for: device))
                .foregroundStyle(device.isConnected ? Color.white : Color.secondary)
        }
        .frame(
            width: BluetoothPanelMetrics.iconColumnWidth,
            height: BluetoothPanelMetrics.iconColumnWidth
        )
        .accessibilityHidden(true)
    }

    private var name: some View {
        Text(device.name)
            .font(.body.weight(device.isConnected ? .semibold : .regular))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private var mobileDetails: some View {
        if let snapshot = mobileMetadataByDeviceID[device.id] {
            MobileBatteryDeviceRows(snapshot: snapshot)
        }
    }

    /// The level as the report's pieces. The charging case is drawn as its glyph
    /// rather than spelled out, so the row is not carrying a word no localization
    /// translates.
    @ViewBuilder
    private var batteryText: some View {
        if let segments = BluetoothDevicePresentation.batteryLevelSegments(
            for: device,
            batteryLevels: batteryLevels
        ) {
            BluetoothBatteryLevelText.drawn(segments)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // The glyph is drawn inside the text run and carries no label of
                // its own, so the run is taken out of the combined element and
                // read back from its text form, in `rowAccessibilityValue`.
                .accessibilityHidden(true)
        }
    }

    /// Only the states `drawsText` accepts reach this: what the row cannot say by
    /// appearance alone.
    @ViewBuilder
    private func statusText(_ status: BluetoothDeviceRowStatus) -> some View {
        switch status {
        case .connecting:
            workingLabel(localization.string(.bluetoothStateConnecting))
        case .disconnecting:
            workingLabel(localization.string(.bluetoothStateDisconnecting))
        case .connectFailed:
            failureLabel(localization.string(.bluetoothStateConnectFailed))
        case .disconnectFailed:
            failureLabel(localization.string(.bluetoothStateDisconnectFailed))
        case .connected, .notConnected:
            EmptyView()
        }
    }

    /// What the row says about itself beyond the text a screen reader can read on
    /// its own: the connection state the glyph and the checkmark carry visually,
    /// and the level.
    ///
    /// The level belongs here because its charging-case glyph is drawn inside a
    /// `Text` run and has no label of its own: a combined element would otherwise
    /// announce the case's percentage with nothing saying what it belongs to.
    private var rowAccessibilityValue: String {
        let state = stateAccessibilityValue
        guard let level = BluetoothDevicePresentation.batteryLevelSegments(
            for: device,
            batteryLevels: batteryLevels
        )?.plainText else {
            return state
        }
        return "\(state), \(level)"
    }

    /// What this row's status says, for the accessibility value that replaced the
    /// visible word.
    private var stateAccessibilityValue: String {
        switch BluetoothDeviceActionPolicy.status(for: device, actionState: actionState) {
        case .connected:
            localization.string(.bluetoothConnected)
        case .notConnected:
            localization.string(.bluetoothNotConnected)
        case .connecting:
            localization.string(.bluetoothStateConnecting)
        case .disconnecting:
            localization.string(.bluetoothStateDisconnecting)
        case .connectFailed:
            localization.string(.bluetoothStateConnectFailed)
        case .disconnectFailed:
            localization.string(.bluetoothStateDisconnectFailed)
        }
    }

    private func workingLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityLabel(text)
    }

    private func failureLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(1)
    }

    /// Whether an action is already running for this device. A failure that is
    /// still on screen is not in flight: tapping it retries.
    private var isActionInFlight: Bool {
        switch actionState {
        case .connecting, .disconnecting: true
        case .failed, .none: false
        }
    }

    private var actionHelp: String {
        BluetoothDeviceActionPolicy.action(for: device) == .connect
            ? localization.string(.bluetoothActionConnect)
            : localization.string(.bluetoothActionDisconnect)
    }

    private func handleTap() {
        guard !isActionInFlight else { return }
        if BluetoothDeviceActionPolicy.requiresConfirmation(for: device) {
            onRequestDisconnect()
        } else {
            onPerformAction()
        }
    }
}
