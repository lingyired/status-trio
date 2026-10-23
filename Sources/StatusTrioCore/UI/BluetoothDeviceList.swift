import SwiftUI

/// The Bluetooth device list shown under the status row. Paired, trusted-mobile,
/// and selected BLE rows share one order, limit, expansion control, and viewport.
/// Only actionable paired rows connect or disconnect; external reading rows stay
/// read-only.
struct BluetoothDeviceList: View {
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let devices: [BluetoothDevice]
    let batteryLevels: [String: BluetoothBatteryLevel]
    var nearbyReadingsByID: [UUID: NearbyBluetoothBatteryDevice] = [:]
    var mobileMetadataByDeviceID: [String: MobileBatterySnapshot] = [:]
    var nearbyRows: [NearbyBLEPanelRow] = []
    var onVisibleNearbyIDsChanged: (Set<UUID>) -> Void = { _ in }
    var appleRows: [AppleDevicePanelRow] = []
    var onVisibleAppleIDsChanged: (Set<AppleDeviceID>) -> Void = { _ in }
    let actionStates: [String: BluetoothDeviceActionState]
    /// The device whose disconnect is waiting for confirmation, by normalized
    /// address. The controller owns it so that closing the panel cancels it even
    /// though the popover keeps this view alive.
    let confirmingAddress: String?
    let options: BluetoothDeviceListOptions
    var listeningModePresentations: [String: BluetoothListeningModePresentation] = [:]
    var onSelectListeningMode: (String, BluetoothListeningMode) -> Void = { _, _ in }
    let onPerformAction: (BluetoothDevice) -> Void
    let onRequestDisconnect: (BluetoothDevice) -> Void
    let onCancelDisconnect: () -> Void

    @State private var isExpanded = false
    @State private var nearbyRowFrames: [UUID: CGRect] = [:]
    @State private var rowsViewportFrame = CGRect.zero
    @State private var reportedNearbyIDs = Set<UUID>()
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var reportedAppleIDs = Set<AppleDeviceID>()

    private struct BluetoothDeviceListVisibilitySnapshot: Equatable {
        let visibleDevices: [BluetoothDevice]
        let displayRows: [BluetoothDisplayRow]
        let appleRows: [AppleDevicePanelRow]
        let options: BluetoothDeviceListOptions
    }

    private var displayRows: [BluetoothDisplayRow] {
        let orderingLevels = BluetoothDeviceListPresentation.includingRowBatteryLevels(
            batteryLevels,
            nearbyRows: nearbyRows,
            appleRows: appleRows
        )
        let sourceModel = BluetoothDeviceListModel.make(
            devices: devices,
            nearbyRows: nearbyRows,
            appleRows: appleRows,
            batteryLevels: orderingLevels,
            order: options.order,
            limit: Int.max,
            isExpanded: true,
            options: options
        )
        let rows = BluetoothDeviceListPresentation.sharedDisplayRows(sourceModel.orderedDevices)
            .filter { row in
                !row.sourceIDs.contains {
                    options.hiddenDeviceAddresses.contains(BluetoothDeviceIdentity.preferenceKey($0))
                }
        }
        let connected = rows.filter { $0.device.isConnected }
        let disconnected = rows.filter { !$0.device.isConnected }
        return BluetoothDeviceListPresentation.orderedDisplayRows(connected, using: options.order, batteryLevels: orderingLevels)
            + BluetoothDeviceListPresentation.orderedDisplayRows(disconnected, using: options.order, batteryLevels: orderingLevels)
    }

    private static let geometryCoordinateSpace = "BluetoothDeviceList"

    /// How tall the rows may grow before they scroll, matching the Wi-Fi list's
    /// own bound so the two lists in the panel stop at the same place.
    static let maximumRowsHeight: CGFloat = 330

    /// The gap between two rows. The rows themselves are not all one height — an
    /// inline row is a single line and a component row adds a second for its
    /// levels — so the list can no longer multiply a fixed pitch by the device
    /// count. `estimatedContentHeight` adds each row's own height up instead.
    private static let rowSpacing: CGFloat = 2

    var body: some View {
        let orderedDisplayDevices = displayRows.map(\.device)
        let visibleDisplayDevices = BluetoothDeviceListPresentation.visibleDevices(
            from: orderedDisplayDevices,
            limit: options.maxVisibleDevices,
            isExpanded: isExpanded
        )
        let visibilitySnapshot = BluetoothDeviceListVisibilitySnapshot(
            visibleDevices: visibleDisplayDevices,
            displayRows: displayRows,
            appleRows: appleRows,
            options: options
        )

        VStack(spacing: Self.rowSpacing) {
            rows(visibleDisplayDevices)

            // Deliberately outside the scroll region: collapsing a long list must
            // not require scrolling to the bottom first.
            if BluetoothDeviceListPresentation.canToggleExpansion(
                for: orderedDisplayDevices,
                limit: options.maxVisibleDevices
            ) {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        PanelActionGlyph(
                            systemName: "chevron.down",
                            font: .caption.weight(.semibold),
                            size: 16
                        )
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))

                        Text(
                            localization.string(
                                isExpanded ? .bluetoothListCollapse : .bluetoothListExpand
                            )
                        )
                        .font(.callout)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .coordinateSpace(name: Self.geometryCoordinateSpace)
        .onPreferenceChange(BluetoothDeviceListRowFramesPreferenceKey.self) { frames in
            rowFrames = frames
            nearbyRowFrames = Dictionary(frames.compactMap { key, frame in
                guard let id = BluetoothDeviceIdentity.bleUUID(from: key) else { return nil }
                return (id, frame)
            }, uniquingKeysWith: { _, latest in latest })
            publishVisibleNearbyIDs(in: visibilitySnapshot)
        }
        .onPreferenceChange(BluetoothDeviceListViewportPreferenceKey.self) { frame in
            rowsViewportFrame = frame
            publishVisibleNearbyIDs(in: visibilitySnapshot)
        }
        .onChange(of: visibilitySnapshot) { snapshot in
            publishVisibleNearbyIDs(in: snapshot)
        }
        .onDisappear {
            reportVisibleNearbyIDs([])
            reportVisibleAppleIDs([])
        }
    }

    /// The rows, bounded.
    ///
    /// The scroll view appears only once the rows outgrow the panel. The summary
    /// popover has no scroll view of its own, so without a bound a long list — an
    /// expanded one, or a limit the user raised — would keep growing the popover
    /// past the screen. A scroll view that is not needed is not free either: its
    /// scroller flashes while an expansion animates through the moment where the
    /// content is taller than the shrinking frame, which a list of six devices
    /// should never show. Below the bound the rows are laid out directly, so
    /// there is nothing to flash. The panel's scroll-wheel handling already
    /// leaves a pointer over an `NSScrollView` to that view instead of adjusting
    /// the volume.
    @ViewBuilder
    private func rows(_ visibleDevices: [BluetoothDevice]) -> some View {
        if estimatedContentHeight(for: visibleDevices) > Self.maximumRowsHeight {
            ScrollView { rowStack(visibleDevices) }
                .frame(maxHeight: Self.maximumRowsHeight)
                .background(viewportFrameReader)
        } else {
            rowStack(visibleDevices)
                .background(viewportFrameReader)
        }
    }

    /// How tall the given rows come to: each row's own estimated height, plus the
    /// spacing between them. This is what decides whether the list scrolls, so a
    /// device set of component rows — taller than the count-based model assumed —
    /// reaches the bound at the right row, not several rows too late.
    private func estimatedContentHeight(for visibleDevices: [BluetoothDevice]) -> CGFloat {
        guard !visibleDevices.isEmpty else { return 0 }
        let rowHeights = visibleDevices.reduce(CGFloat(0)) { total, device in
            let mobileSnapshot = mobileMetadata(for: device)[device.id]
            let hasMobileDetailLine = mobileSnapshot.map {
                MobileBatteryDeviceRowPresentation.detailText(
                    $0,
                    charging: localization.string(.mobileBatteryCharging)
                ) != nil
            } ?? false
            let address = BluetoothBatteryReader.normalizedAddress(device.id)
            let modeHeight: CGFloat = device.isHuaweiAudio
                && listeningModePresentations[address]?.isControllable == true ? 23 : 0
            return total + modeHeight + BluetoothDeviceRowMetrics.estimatedHeight(
                for: device,
                batteryLevels: batteryLevels,
                hasMobileDetailLine: hasMobileDetailLine
            )
        }
        return rowHeights + Self.rowSpacing * CGFloat(visibleDevices.count - 1)
    }

    private func rowStack(_ visibleDevices: [BluetoothDevice]) -> some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(visibleDevices) { device in
                let address = BluetoothBatteryReader.normalizedAddress(device.id)
                BluetoothDeviceRow(
                    device: device,
                    batteryLevels: batteryLevels(for: device),
                    mobileMetadataByDeviceID: mobileMetadata(for: device),
                    nearbyMetadataByDeviceID: nearbyMetadata(for: device),
                    appleStatusByDeviceID: appleStatus(for: device),
                    canonicalStatusByDeviceID: canonicalStatus(for: device),
                    listeningMode: listeningModePresentations[address],
                    onSelectListeningMode: { onSelectListeningMode(address, $0) },
                    actionState: actionStates[address],
                    isConfirmingDisconnect: confirmingAddress == address
                        && BluetoothDeviceActionPolicy.requiresConfirmation(for: device),
                    onPerformAction: { onPerformAction(device) },
                    onRequestDisconnect: { onRequestDisconnect(device) },
                    onCancelDisconnect: onCancelDisconnect
                )
                .background {
                    if device.isReadOverTheAir {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: BluetoothDeviceListRowFramesPreferenceKey.self,
                                value: [device.id: proxy.frame(in: .named(Self.geometryCoordinateSpace))]
                            )
                        }
                    }
                }
            }
        }
    }

    private var nearbyRowByDeviceID: [String: NearbyBLEPanelRow] {
        Dictionary(nearbyRows.map { ($0.device.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    private func mobileMetadata(for device: BluetoothDevice) -> [String: MobileBatterySnapshot] {
        guard let displayRow = displayRows.first(where: { $0.device.id == device.id }) else {
            return mobileMetadataByDeviceID
        }
        var values = mobileMetadataByDeviceID
        let snapshots = displayRow.sourceIDs.compactMap { mobileMetadataByDeviceID[$0] }
        let selectedSnapshot = selectedReading(for: displayRow).flatMap { selected in
            snapshots.first { $0.observedAt == selected.observedAt && $0.batteryLevel == selected.level }
        }
        if let snapshot = selectedSnapshot ?? snapshots.max(by: { $0.observedAt < $1.observedAt }) {
            values[device.id] = snapshot
        } else {
            values.removeValue(forKey: device.id)
        }
        return values
    }

    private func batteryLevels(for device: BluetoothDevice) -> [String: BluetoothBatteryLevel] {
        guard let displayRow = displayRows.first(where: { $0.device.id == device.id }) else { return batteryLevels }
        var values = batteryLevels
        if let selected = selectedReading(for: displayRow) {
            values[BluetoothBatteryReader.normalizedAddress(device.id)] = BluetoothBatteryLevel(
                deviceAddress: device.id, main: selected.level, left: nil, right: nil, caseLevel: nil
            )
        }
        return values
    }

    private func nearbyMetadata(for device: BluetoothDevice) -> [String: NearbyBLEPanelRow] {
        guard let displayRow = displayRows.first(where: { $0.device.id == device.id }) else { return nearbyRowByDeviceID }
        var values = nearbyRowByDeviceID
        if let sourceRow = displayRow.sourceIDs.compactMap({ sourceID in
            BluetoothDeviceIdentity.bleUUID(from: sourceID)
                .flatMap { uuid in nearbyRows.first(where: { $0.id == uuid }) }
        }).first {
            values[device.id] = NearbyBLEPanelRow(
                id: sourceRow.id, device: device, batteryLevel: sourceRow.batteryLevel,
                wasSeenRecently: sourceRow.wasSeenRecently, readFailed: sourceRow.readFailed,
                batteryLevelsEnabled: sourceRow.batteryLevelsEnabled, observedAt: sourceRow.observedAt
            )
        }
        return values
    }

    private func appleStatus(for device: BluetoothDevice) -> [String: NearbyBLEPanelRowStatus] {
        var values = Dictionary(appleRows.map { ($0.device.id, $0.status) }, uniquingKeysWith: { _, latest in latest })
        guard let displayRow = displayRows.first(where: { $0.device.id == device.id }) else { return values }
        if let selected = selectedReading(for: displayRow) {
            values[device.id] = .battery(selected.level)
        } else if let row = appleRows.first(where: { displayRow.sourceIDs.contains($0.device.id) }) {
            values[device.id] = row.status
        }
        return values
    }

    private func canonicalStatus(for device: BluetoothDevice) -> [String: NearbyBLEPanelRowStatus] {
        guard let displayRow = displayRows.first(where: { $0.device.id == device.id }),
              let reading = selectedReading(for: displayRow) else { return [:] }
        return [device.id: .battery(reading.level)]
    }

    private func selectedReading(for row: BluetoothDisplayRow) -> BluetoothDisplayBatteryReading? {
        BluetoothDeviceListPresentation.newestValidReading(
            for: row,
            nearbyReadings: Array(nearbyReadingsByID.values),
            nearbyRows: nearbyRows,
            trustedSnapshots: Array(mobileMetadataByDeviceID.values)
        )
    }

    private var viewportFrameReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: BluetoothDeviceListViewportPreferenceKey.self,
                value: proxy.frame(in: .named(Self.geometryCoordinateSpace))
            )
        }
    }

    private func publishVisibleNearbyIDs(in snapshot: BluetoothDeviceListVisibilitySnapshot) {
        var nearbyIDs = NearbyBLEPanelVisibility.visibleSelectedIDs(
            in: snapshot.visibleDevices,
            frames: nearbyRowFrames,
            viewport: rowsViewportFrame
        )
        var appleIDs = AppleDevicePanelVisibility.visibleIDs(
            in: snapshot.visibleDevices,
            rowIDs: AppleDeviceCatalog.rowIdentityMap(snapshot.appleRows),
            frames: rowFrames,
            viewport: rowsViewportFrame
        )
        let visibleIDs = Set(snapshot.visibleDevices.map(\.id))
        for row in snapshot.displayRows where visibleIDs.contains(row.device.id) {
            for sourceID in row.sourceIDs {
                if let uuid = BluetoothDeviceIdentity.bleUUID(from: sourceID) { nearbyIDs.insert(uuid) }
                if let appleID = snapshot.appleRows.first(where: { $0.device.id == sourceID })?.id {
                    appleIDs.insert(appleID)
                }
            }
        }
        reportVisibleNearbyIDs(nearbyIDs)
        reportVisibleAppleIDs(appleIDs)
    }

    private func reportVisibleNearbyIDs(_ ids: Set<UUID>) {
        guard reportedNearbyIDs != ids else { return }
        reportedNearbyIDs = ids
        onVisibleNearbyIDsChanged(ids)
    }

    private func reportVisibleAppleIDs(_ ids: Set<AppleDeviceID>) {
        guard reportedAppleIDs != ids else { return }
        reportedAppleIDs = ids
        onVisibleAppleIDsChanged(ids)
    }
}

private struct BluetoothDeviceListRowFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct BluetoothDeviceListViewportPreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        guard next.width > 0, next.height > 0 else { return }
        value = next
    }
}
