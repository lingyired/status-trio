import XCTest
@testable import StatusTrioCore

/// Manual BetterDisplay display picker for brightness (#313).
final class BetterDisplayBrightnessSettingsTests: XCTestCase {
    private func state(
        backend: BrightnessBackend = .betterDisplay,
        uuid: String? = nil,
        devices: [BetterDisplayDevice] = [],
        loaded: Bool = true
    ) -> BetterDisplayBrightnessSettingsState {
        BetterDisplayBrightnessSettingsState(
            configuration: ExternalBrightnessConfiguration(
                backend: backend,
                betterDisplayUUID: uuid
            ),
            devices: devices,
            hasLoadedCatalog: loaded
        )
    }

    func testPickerOnlyShowsForBetterDisplayBackend() {
        XCTAssertTrue(state(backend: .betterDisplay).showsDisplayPicker)
        XCTAssertFalse(state(backend: .automatic).showsDisplayPicker)
        XCTAssertFalse(state(backend: .directDDC).showsDisplayPicker)
        XCTAssertFalse(state(backend: .displayServices).showsDisplayPicker)
    }

    func testSelectedUUIDIsTrimmedAndBlankBecomesNil() {
        XCTAssertEqual(state(uuid: "  ABC-123  ").selectedDisplayUUID, "ABC-123")
        XCTAssertNil(state(uuid: "   ").selectedDisplayUUID)
        XCTAssertNil(state(uuid: nil).selectedDisplayUUID)
    }

    func testPickerOptionsStartWithAutomaticThenDevices() {
        let options = state(devices: [
            BetterDisplayDevice(uuid: "u1", name: "Redmi 27 NU"),
            BetterDisplayDevice(uuid: "u2", name: nil),
        ]).pickerOptions

        XCTAssertEqual(options.first, .unassociated)
        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options[1], .device(uuid: "u1", name: "Redmi 27 NU"))
        XCTAssertEqual(options[2], .device(uuid: "u2", name: nil))
    }

    func testDuplicateDeviceUUIDsAreCollapsed() {
        let options = state(devices: [
            BetterDisplayDevice(uuid: "u1", name: "A"),
            BetterDisplayDevice(uuid: "u1", name: "A"),
        ]).pickerOptions
        XCTAssertEqual(options, [.unassociated, .device(uuid: "u1", name: "A")])
    }

    func testSavedUUIDMissingFromLoadedCatalogShowsUnavailable() {
        let options = state(uuid: "gone", devices: [], loaded: true).pickerOptions
        XCTAssertEqual(options, [.unassociated, .unavailable(uuid: "gone")])
    }

    func testSavedUUIDBeforeCatalogLoadsShowsSaved() {
        let options = state(uuid: "gone", devices: [], loaded: false).pickerOptions
        XCTAssertEqual(options, [.unassociated, .saved(uuid: "gone")])
    }

    func testDeviceLabelDisambiguatesDuplicateNamesByUUID() {
        let state = state(devices: [
            BetterDisplayDevice(uuid: "AAAA1111", name: "Redmi 27 NU"),
            BetterDisplayDevice(uuid: "BBBB2222", name: "Redmi 27 NU"),
        ])
        XCTAssertEqual(
            state.deviceLabel(uuid: "AAAA1111", name: "Redmi 27 NU"),
            "Redmi 27 NU · AAAA1111"
        )
    }

    func testDeviceLabelKeepsUniqueNameAndNilName() {
        let state = state(devices: [
            BetterDisplayDevice(uuid: "u1", name: "Only One"),
        ])
        XCTAssertEqual(state.deviceLabel(uuid: "u1", name: "Only One"), "Only One")
        XCTAssertNil(state.deviceLabel(uuid: "u9", name: nil))
    }
}
