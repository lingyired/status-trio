import SwiftUI

/// The Bluetooth device list shown under the status row. Paired, trusted-mobile,
/// and selected BLE rows share one order and a bounded main list with overflow.
/// Only actionable paired rows connect or disconnect; external reading rows stay
/// read-only.
struct BluetoothDeviceList: View {
    @EnvironmentObject private var localization: Localization
    /// True when the panel already owns an outer scroll surface (#237). The list
    /// must then draw every row directly instead of adding a second scroller.
    @Environment(\.statusPanelManagesScrolling) private var statusPanelManagesScrolling
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

    /// Persists the collapsed list's layout after a real read so the panel can
    /// draw an equal-height skeleton the next time it reopens.
    var layoutSnapshots: PanelListLayoutSnapshotStore = PanelListLayoutSnapshotStore()
    /// Only record a snapshot once the controller has a real device read; a
    /// still-loading or empty placeholder list must never overwrite the cache.
    var recordsLayoutSnapshot = true
    /// Addresses of cached, connected AirPods rows that should reserve a battery
    /// line while their level is being read.
    var batteryPlaceholderAddresses: Set<String> = []

    @State private var isOverflowPresented = false
    @State private var isVisible = false
    @State private var mainDemand = VisibilityDemand()
    @State private var overflowDemand = VisibilityDemand()
    @State private var reportedNearbyIDs = Set<UUID>()
    @State private var reportedAppleIDs = Set<AppleDeviceID>()

    static func partition(
        _ devices: [BluetoothDevice], limit: Int
    ) -> (main: [BluetoothDevice], overflow: [BluetoothDevice]) {
        let count = max(0, limit)
        return (Array(devices.prefix(count)), Array(devices.dropFirst(count)))
    }

    /// Each hosting tree reports only intersecting canonical rows. Alias IDs
    /// inherit that visibility; a closed overflow never authorizes a late report.
    struct VisibilityDemand: Equatable {
        var nearbyIDs = Set<UUID>()
        var appleIDs = Set<AppleDeviceID>()

        static func visible(
            rows: [BluetoothDisplayRow], frames: [String: CGRect],
            viewport: CGRect, appleRowIDs: [String: AppleDeviceID]
        ) -> Self {
            guard viewport.width > 0, viewport.height > 0 else { return Self() }
            var demand = Self()
            for row in rows {
                guard let frame = frames[row.device.id], frame.width > 0, frame.height > 0,
                      frame.intersects(viewport) else { continue }
                for sourceID in row.sourceIDs {
                    if let id = BluetoothDeviceIdentity.bleUUID(from: sourceID) {
                        demand.nearbyIDs.insert(id)
                    }
                    if let id = appleRowIDs[sourceID] { demand.appleIDs.insert(id) }
                }
            }
            return demand
        }

        static func combining(main: Self, overflow: Self, isOverflowPresented: Bool) -> Self {
            guard isOverflowPresented else { return main }
            return Self(
                nearbyIDs: main.nearbyIDs.union(overflow.nearbyIDs),
                appleIDs: main.appleIDs.union(overflow.appleIDs)
            )
        }
    }

    /// Identity for the persisted layout. `.task(id:)` rewrites the snapshot only
    /// when the collapsed row heights, the expansion control, or the loaded flag
    /// actually change, so a periodic refresh does not hit `UserDefaults`.
    private struct LayoutPersistenceID: Equatable {
        let rowHeights: [Double]
        let hasExpansionButton: Bool
        let isLoaded: Bool
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
        let partition = Self.partition(orderedDisplayDevices, limit: options.maxVisibleDevices)
        // Persist only the main list so reopening reserves the collapsed height.
        let collapsedVisibleDevices = partition.main
        let layoutPersistenceID = LayoutPersistenceID(
            rowHeights: collapsedVisibleDevices.map { Double(estimatedRowHeight(for: $0)) },
            hasExpansionButton: BluetoothDeviceListPresentation.canToggleExpansion(
                for: orderedDisplayDevices,
                limit: options.maxVisibleDevices
            ),
            isLoaded: recordsLayoutSnapshot
        )

        VStack(spacing: Self.rowSpacing) {
            rows(partition.main)

            if !partition.overflow.isEmpty {
                CascadingSubmenuButton(
                    title: localization.string(.bluetoothListExpand),
                    isPresented: $isOverflowPresented
                ) {
                    rowStack(partition.overflow, isOverflow: true)
                }
            }
        }
        .onAppear {
            isVisible = true
            publishVisibleIDs()
        }
        .onChange(of: isOverflowPresented) { presented in
            if !presented { overflowDemand = VisibilityDemand() }
            publishVisibleIDs()
        }
        .task(id: layoutPersistenceID) {
            guard layoutPersistenceID.isLoaded else { return }
            let snapshot = PanelListLayoutSnapshot(
                rowHeights: layoutPersistenceID.rowHeights,
                hasExpansionButton: layoutPersistenceID.hasExpansionButton,
                showsDeviceList: true
            )
            layoutSnapshots.save(snapshot.isEmpty ? nil : snapshot, for: .bluetooth)
        }
        .onDisappear {
            isVisible = false
            isOverflowPresented = false
            mainDemand = VisibilityDemand()
            overflowDemand = VisibilityDemand()
            reportVisibleNearbyIDs([])
            reportVisibleAppleIDs([])
        }
    }

    /// The rows, bounded when this list is used on its own.
    ///
    /// The scroll view appears only once the rows outgrow the bound. A scroll
    /// view that is not needed is not free either: its scroller flashes while an
    /// expansion animates through the moment where the content is taller than
    /// the shrinking frame, which a list of six devices should never show.
    /// Below the bound the rows are laid out directly, so there is nothing to
    /// flash. When the status panel itself owns the outer scroll surface, the
    /// list must not bound or scroll at all (#237): the panel needs the rows'
    /// natural height to decide whether one outer scroller is necessary. The
    /// panel's scroll-wheel handling already leaves a pointer over an
    /// `NSScrollView` to that view instead of adjusting the volume.
    @ViewBuilder
    private func rows(_ visibleDevices: [BluetoothDevice]) -> some View {
        if statusPanelManagesScrolling {
            rowStack(visibleDevices)
        } else if estimatedContentHeight(for: visibleDevices) > Self.maximumRowsHeight {
            ScrollView { rowStack(visibleDevices) }
                .frame(maxHeight: Self.maximumRowsHeight)
        } else {
            rowStack(visibleDevices)
        }
    }

    /// How tall the given rows come to: each row's own estimated height, plus the
    /// spacing between them. This is what decides whether the list scrolls, so a
    /// device set of component rows — taller than the count-based model assumed —
    /// reaches the bound at the right row, not several rows too late.
    private func estimatedContentHeight(for visibleDevices: [BluetoothDevice]) -> CGFloat {
        guard !visibleDevices.isEmpty else { return 0 }
        let rowHeights = visibleDevices.reduce(CGFloat(0)) { total, device in
            total + estimatedRowHeight(for: device)
        }
        return rowHeights + Self.rowSpacing * CGFloat(visibleDevices.count - 1)
    }

    /// The height one device row contributes, matching the height the row itself
    /// draws with. Shared by the scroll bound and the persisted layout snapshot so
    /// the skeleton is never a different height from the row it replaces.
    private func estimatedRowHeight(for device: BluetoothDevice) -> CGFloat {
        let address = BluetoothBatteryReader.normalizedAddress(device.id)
        // A cached AirPods row reserves the two-line height while its level is
        // still being read, so the scroll bound matches what it will draw.
        if batteryPlaceholderAddresses.contains(address) {
            return BluetoothDeviceRowMetrics.componentHeight
        }
        let mobileSnapshot = mobileMetadata(for: device)[device.id]
        let hasMobileDetailLine = mobileSnapshot.map {
            MobileBatteryDeviceRowPresentation.detailText(
                $0,
                charging: localization.string(.mobileBatteryCharging)
            ) != nil
        } ?? false
        let modeHeight: CGFloat = device.isHuaweiAudio
            && listeningModePresentations[address]?.isControllable == true ? 23 : 0
        return modeHeight + BluetoothDeviceRowMetrics.estimatedHeight(
            for: device,
            batteryLevels: batteryLevels,
            hasMobileDetailLine: hasMobileDetailLine
        )
    }

    private func rowStack(_ visibleDevices: [BluetoothDevice], isOverflow: Bool = false) -> some View {
        let visibleIDs = Set(visibleDevices.map(\.id))
        return BluetoothListVisibilityRegion(
            rows: displayRows.filter { visibleIDs.contains($0.device.id) },
            appleRowIDs: AppleDeviceCatalog.rowIdentityMap(appleRows),
            onChange: { demand in
                if isOverflow { overflowDemand = demand } else { mainDemand = demand }
                publishVisibleIDs()
            }
        ) {
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
                        showsBatteryPlaceholder: batteryPlaceholderAddresses.contains(address),
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
                                    key: BluetoothListVisibilityRegionRowFramesKey.self,
                                    value: [device.id: proxy.frame(in: .named(BluetoothListVisibilityCoordinateSpace.rows))]
                                )
                            }
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

    private func publishVisibleIDs() {
        guard isVisible else { return }
        let demand = VisibilityDemand.combining(
            main: mainDemand, overflow: overflowDemand, isOverflowPresented: isOverflowPresented
        )
        reportVisibleNearbyIDs(demand.nearbyIDs)
        reportVisibleAppleIDs(demand.appleIDs)
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
