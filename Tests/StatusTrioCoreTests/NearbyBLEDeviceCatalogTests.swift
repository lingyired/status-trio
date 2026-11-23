import Foundation
import Testing
@testable import StatusTrioCore

struct NearbyBLEDeviceCatalogTests {
    @Test func candidateOnlyMetadataDoesNotCreatePanelRows() {
        let selection = selection(name: "My Phone", vendor: .apple)

        let rows = NearbyBLEDeviceCatalog.panelRows(
            selections: [selection],
            readings: [],
            failures: [],
            options: .standard,
            now: Date()
        )

        #expect(rows.isEmpty)
    }

    @Test func zeroBatteryIsDifferentFromMissingAndExpiredReading() {
        let now = Date(timeIntervalSince1970: 10_000)
        let zero = selection(name: "Zero", verifiedAt: now)
        let missing = selection(name: "Missing")
        let expired = selection(name: "Expired", verifiedAt: now.addingTimeInterval(-1801))
        let rows = NearbyBLEDeviceCatalog.panelRows(
            selections: [zero, missing, expired],
            readings: [
                reading(zero.id, name: zero.name, level: 0, updatedAt: now),
                reading(expired.id, name: expired.name, level: 78, updatedAt: now.addingTimeInterval(-1_801))
            ],
            failures: [],
            options: .standard,
            now: now
        )

        #expect(rows.map(\.id) == [zero.id])
        #expect(rows.map(\.batteryLevel) == [0])
    }

    @Test func failedReadDoesNotGiveNearbyRowAnExtraStatus() {
        let failed = selection(name: "Nearby phone")
        let rows = NearbyBLEDeviceCatalog.panelRows(
            selections: [failed], readings: [], failures: [failed.id],
            options: .standard, now: Date()
        )

        #expect(rows.isEmpty, "a failed first read must not create a row")
    }

    @Test func persistedNearbyRowsAreHiddenUntilBluetoothCanBeRead() {
        let saved = selection(name: "Cached phone", verifiedAt: Date())

        for availability: BluetoothAvailability in [
            .idle, .initializing, .authorizationNotDetermined, .authorizationDenied,
            .authorizationRestricted, .poweredOff, .unavailable, .failed
        ] {
            #expect(
                NearbyBLEDeviceCatalog.revealedSelections(
                    [saved], enabled: true, availability: availability
                ).isEmpty,
                "a cached level must not back \(availability)"
            )
        }
        #expect(
            NearbyBLEDeviceCatalog.revealedSelections(
                [saved], enabled: true, availability: .available
            ).map(\.id) == [saved.id]
        )
        #expect(
            NearbyBLEDeviceCatalog.revealedSelections(
                [saved], enabled: false, availability: .available
            ).isEmpty
        )
    }

    @Test func disabledBatteryPresentationRetainsCachedIdentityButHidesBatteryAndFailure() {
        let now = Date(timeIntervalSince1970: 15_000)
        let selected = NearbyBLEDeviceSelection(
            id: UUID(), name: "iPhone", vendor: .apple, model: "iPhone6,2",
            batteryLevel: 84, batteryLastUpdated: now
        )
        let failed = selection(name: "Other")
        let rows = NearbyBLEDeviceCatalog.panelRows(
            selections: [selected, failed],
            readings: [reading(selected.id, name: selected.name, level: 84, updatedAt: now)],
            failures: [failed.id],
            options: .standard,
            now: now,
            batteryLevelsEnabled: false
        )

        #expect(rows.map(\.batteryLevel) == [84], "the cached value remains attached to the validated row")
        #expect(rows[0].device.appleMobileModel == "iPhone6,2")
        #expect(rows.allSatisfy { $0.presentationStatus == nil }, "visual and accessible battery status is suppressed")
    }

    @Test func hiddenRowsAreFilteredAndSavedOrderBeatsAppleFirstDiscoveryOrder() {
        let apple = selection(name: "Apple", vendor: .apple, verifiedAt: Date())
        let other = selection(name: "Other", vendor: .apple, verifiedAt: Date())
        let hidden = selection(name: "Hidden", verifiedAt: Date())
        let options = BluetoothDeviceListOptions(
            showsList: true,
            maxVisibleDevices: 5,
            order: [BluetoothDeviceIdentity.bleRowID(other.id), BluetoothDeviceIdentity.bleRowID(apple.id)],
            hiddenDeviceAddresses: [BluetoothDeviceIdentity.bleRowID(hidden.id)]
        )
        let rows = NearbyBLEDeviceCatalog.panelRows(
            selections: [apple, other, hidden],
            readings: [],
            failures: [hidden.id],
            options: options,
            now: Date()
        )

        #expect(rows.map(\.id) == [other.id, apple.id])
        #expect(rows.map(\.wasSeenRecently) == [false, false])
        #expect(rows.allSatisfy { !$0.readFailed })
    }

    @Test func sameNamedSelectedUUIDsStayDistinctFromEachOtherAndSystemRows() {
        let first = selection(name: "Shared Name", verifiedAt: Date())
        let second = selection(name: "Shared Name", verifiedAt: Date())
        let rows = NearbyBLEDeviceCatalog.panelRows(
            selections: [first, second],
            readings: [],
            failures: [],
            options: .standard,
            now: Date()
        )
        let system = BluetoothDevice(id: "AA:BB:CC:DD:EE:FF", name: "Shared Name", kind: .mobile(.phone), isConnected: true)

        #expect(rows.count == 2)
        #expect(rows[0].device.name == system.name && rows[1].device.name == system.name)
        #expect(rows[0].id != rows[1].id)
        #expect(rows.allSatisfy { !$0.device.isConnected })
        #expect(rows.allSatisfy { $0.device.id != system.id })
    }

    @Test func failedReadIsAttachedOnlyToFreshValidatedRows() {
        let now = Date(timeIntervalSince1970: 20_000)
        let fresh = selection(name: "Fresh", verifiedAt: now)
        let stale = selection(name: "Stale", verifiedAt: now)
        let stranger = UUID()
        let rows = NearbyBLEDeviceCatalog.panelRows(
            selections: [fresh, stale],
            readings: [],
            failures: [fresh.id, stranger],
            options: .standard,
            now: now
        )

        #expect(rows.map(\.wasSeenRecently) == [false, false])
        #expect(rows.map(\.readFailed) == [true, false])
    }

    @Test func settingsDevicesExcludeGhostsAndShowNamedAppleMetadataAsOrdinaryRows() {
        let first = selection(name: "Same", vendor: .apple, verifiedAt: Date())
        let second = selection(name: "Same", vendor: .apple, verifiedAt: Date())
        let nonApple = selection(name: "Mouse", vendor: .other)
        let ghost = BluetoothDevice(id: "AA:00:00:00:00:01", name: "Ghost", kind: .unknown, isConnected: false, isUnpairedGhost: true)
        let paired = BluetoothDevice(id: "AA:00:00:00:00:02", name: "Keyboard", kind: .unknown, isConnected: false)
        let devices = NearbyBLEDeviceCatalog.settingsDevices([ghost, paired], selections: [first, second, nonApple])

        #expect(devices.map(\.id) == [paired.id, BluetoothDeviceIdentity.bleRowID(first.id), BluetoothDeviceIdentity.bleRowID(second.id)])
        #expect(devices.filter(\.isReadOverTheAir).allSatisfy { $0.kind == .unknown && !$0.isConnected })
        #expect(!devices.contains { $0.id == ghost.id || $0.name == nonApple.name })
    }

    @Test func discoveredAppleMetadataDeduplicatesPersistedAndRefreshedUUIDs() {
        let existingID = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!
        let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000072")!
        let existing = [
            NearbyBLEDeviceSelection(id: existingID, name: "Old name", vendor: .apple, model: "iPhone18,1"),
            NearbyBLEDeviceSelection(id: existingID, name: "Duplicate old name", vendor: .apple, model: nil),
            NearbyBLEDeviceSelection(id: otherID, name: "Other phone", vendor: .apple, model: "iPad16,1")
        ]
        let live = [NearbyBLEDeviceCandidate(
            id: existingID, name: "Current name", vendor: .apple, lastSeen: Date(timeIntervalSince1970: 100)
        )]

        let refreshed = NearbyBLEDeviceCatalog.discoveredAppleMetadata(from: live, existing: existing)
        let refreshedAgain = NearbyBLEDeviceCatalog.discoveredAppleMetadata(from: live, existing: refreshed)

        #expect(refreshed.map(\.id) == [existingID, otherID])
        #expect(refreshed[0].name == "Current name")
        #expect(refreshed[0].model == "iPhone18,1")
        #expect(refreshedAgain == refreshed)
    }

    @Test func candidatesStayInvisibleUntilAValidBatteryReadingExistsAndRowsExpireAfterThreeMinutes() {
        let now = Date(timeIntervalSince1970: 50_000)
        let lifetime = BluetoothLEBatteryScanPolicy.resultLifetime
        let current = selection(name: "Current", verifiedAt: now.addingTimeInterval(-lifetime))
        let expired = selection(name: "Expired", verifiedAt: now.addingTimeInterval(-(lifetime + 1)))
        let rows = NearbyBLEDeviceCatalog.panelRows(
            selections: [current, expired],
            readings: [
                reading(current.id, name: current.name, level: 75, updatedAt: now),
                reading(expired.id, name: expired.name, level: 42, updatedAt: now.addingTimeInterval(-(lifetime + 1)))
            ],
            failures: [], options: .standard, now: now
        )

        #expect(rows.map(\.id) == [current.id])
        #expect(rows[0].batteryLevel == 75)
        #expect(NearbyBLEDeviceCatalog.settingsCandidates(selections: [], now: now).isEmpty)
        #expect(NearbyBLEDeviceCatalog.settingsDevices([], selections: []).isEmpty)
    }

    @Test func disablingBatteryReadsKeepsPreviouslyValidatedRowVisibleUntilExpiry() {
        let now = Date(timeIntervalSince1970: 60_000)
        let validated = selection(name: "Previously read", verifiedAt: now)
        let rows = NearbyBLEDeviceCatalog.panelRows(
            selections: [validated],
            readings: [reading(validated.id, name: validated.name, level: 51, updatedAt: now)],
            failures: [], options: .standard, now: now, batteryLevelsEnabled: false
        )

        #expect(rows.map(\.id) == [validated.id])
        #expect(rows[0].batteryLevel == 51)
        #expect(rows[0].presentationStatus == nil)
    }

    @Test func nextVerifiedRowExpirationIgnoresExpiredRowsWhenFutureRowsRemain() {
        let now = Date(timeIntervalSince1970: 80_000)
        let lifetime = BluetoothLEBatteryScanPolicy.resultLifetime
        let expired = selection(name: "Expired", verifiedAt: now.addingTimeInterval(-(lifetime + 1)))
        let future = selection(name: "Future", verifiedAt: now.addingTimeInterval(-60))
        let allExpired = selection(name: "Also expired", verifiedAt: now.addingTimeInterval(-(lifetime + 1)))

        #expect(NearbyBLEDeviceCatalog.nextVerifiedRowExpiration(
            selections: [expired, future], now: now
        ) == now.addingTimeInterval(lifetime - 60))
        #expect(NearbyBLEDeviceCatalog.nextVerifiedRowExpiration(
            selections: [expired, allExpired], now: now
        ) == nil)
    }

    // MARK: - Nearby BLE result lifetime

    /// Issue #249: a nearby row may only outlive its reading by a few minutes,
    /// not the twenty it used to. Bound the constant instead of pinning an exact
    /// number, so a future tuning that stays inside the agreed range is allowed.
    @Test func nearbyResultLifetimeStaysWithinAFewMinutes() {
        #expect(BluetoothLEBatteryScanPolicy.resultLifetime >= 120)
        #expect(BluetoothLEBatteryScanPolicy.resultLifetime <= 180)
    }

    private func selection(
        name: String,
        vendor: NearbyBLEVendor = .apple,
        verifiedAt: Date? = nil
    ) -> NearbyBLEDeviceSelection {
        NearbyBLEDeviceSelection(
            id: UUID(), name: name, vendor: vendor, model: nil,
            batteryLevel: verifiedAt == nil ? nil : 50,
            batteryLastUpdated: verifiedAt
        )
    }

    private func reading(_ id: UUID, name: String, level: Int, updatedAt: Date) -> NearbyBluetoothBatteryDevice {
        NearbyBluetoothBatteryDevice(id: id, name: name, batteryLevel: level, model: nil, manufacturer: nil, lastUpdated: updatedAt)
    }

    private func candidate(
        _ id: UUID,
        name: String,
        vendor: NearbyBLEVendor,
        seenAt: Date = Date()
    ) -> NearbyBLEDeviceCandidate {
        NearbyBLEDeviceCandidate(id: id, name: name, vendor: vendor, lastSeen: seenAt)
    }
}
