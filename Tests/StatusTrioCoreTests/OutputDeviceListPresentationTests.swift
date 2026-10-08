import CoreAudio
import XCTest
@testable import StatusTrioCore

final class OutputDeviceListPresentationTests: XCTestCase {
    func testCollapsedListLimitsVisibleDevices() {
        let devices = makeDevices(count: 6)

        let visibleDevices = OutputDeviceListPresentation.visibleDevices(
            from: devices,
            limit: 5,
            isExpanded: false
        )

        XCTAssertEqual(visibleDevices.map(\.id), [1, 2, 3, 4, 5])
        XCTAssertTrue(
            OutputDeviceListPresentation.canToggleExpansion(
                for: devices,
                limit: 5
            )
        )
    }

    func testExpandedListShowsEveryDevice() {
        let devices = makeDevices(count: 6)

        let visibleDevices = OutputDeviceListPresentation.visibleDevices(
            from: devices,
            limit: 5,
            isExpanded: true
        )

        XCTAssertEqual(visibleDevices.map(\.id), [1, 2, 3, 4, 5, 6])
    }

    func testUnlimitedListDoesNotOfferExpansion() {
        let devices = makeDevices(count: 6)

        XCTAssertEqual(
            OutputDeviceListPresentation.visibleDevices(
                from: devices,
                limit: nil,
                isExpanded: false
            ).map(\.id),
            [1, 2, 3, 4, 5, 6]
        )
        XCTAssertFalse(
            OutputDeviceListPresentation.canToggleExpansion(
                for: devices,
                limit: nil
            )
        )
    }

    func testModelOrdersAndLimitsDevicesOnce() {
        let devices = makeDevices(count: 4)

        let model = OutputDeviceListModel.make(
            devices: devices,
            order: ["device-4", "device-2"],
            limit: 2,
            isExpanded: false
        )

        XCTAssertEqual(model.orderedDevices.map(\.id), [4, 2, 1, 3])
        XCTAssertEqual(model.visibleDevices.map(\.id), [4, 2])
        XCTAssertTrue(model.canToggleExpansion)
    }

    func testOrderKeepsDuplicateAndMissingUIDsStableAfterConfiguredDevices() {
        let devices = [
            AudioOutputDevice(id: 1, name: "One", uid: nil, isCurrent: false),
            AudioOutputDevice(id: 2, name: "Two A", uid: "shared", isCurrent: false),
            AudioOutputDevice(id: 3, name: "Three", uid: "other", isCurrent: false),
            AudioOutputDevice(id: 4, name: "Two B", uid: "shared", isCurrent: true),
            AudioOutputDevice(id: 5, name: "Five", uid: nil, isCurrent: false)
        ]

        let ordered = OutputDeviceListPresentation.orderedDevices(
            devices,
            using: ["shared", "shared"]
        )

        XCTAssertEqual(ordered.map(\.id), [2, 4, 1, 3, 5])
    }

    private func makeDevices(count: Int) -> [AudioOutputDevice] {
        (1...count).map { index in
            AudioOutputDevice(
                id: AudioDeviceID(index),
                name: "Device \(index)",
                uid: "device-\(index)",
                isCurrent: index == 1
            )
        }
    }
}
