import Testing
@testable import StatusTrioCore

@MainActor
struct BetterDisplaySetupPresentationTests {
    @Test
    func exactCurrentOutputAssociationHidesManualPickerButOtherSavedDisplaysRemainEditable() {
        let runtime = BetterDisplayCatalogUpdate(
            devices: [.init(uuid: "display-a", name: "Desk")],
            availability: .available, isCatalogLoaded: true,
            outputUID: "audio-a", displayUUID: "display-a",
            canSetVolume: true, automaticDisplayUUID: "display-a"
        )
        func state(saved: String?) -> BetterDisplayVolumeSettingsState {
            .init(
                outputUID: "audio-a",
                configuration: .init(backend: .betterDisplay, betterDisplayUUID: saved),
                devices: runtime.devices, availability: runtime.availability, runtime: runtime
            )
        }
        #expect(!state(saved: "display-a").showsDisplayPicker)
        #expect(state(saved: "manual-display").showsDisplayPicker)
        #expect(state(saved: nil).setupStatus == .checking)
        #expect(!state(saved: nil).showsDisplayPicker)
        let unmatched = BetterDisplayVolumeSettingsState(
            outputUID: "audio-b", configuration: .init(backend: .betterDisplay, betterDisplayUUID: nil),
            devices: runtime.devices, availability: .deviceUnassociated
        )
        #expect(unmatched.showsDisplayPicker)
    }
    @Test
    func discoveringDoesNotOfferAnEmptyDisplayPicker() {
        let state = BetterDisplayVolumeSettingsState(
            outputUID: "audio-a",
            configuration: ExternalVolumeConfiguration(backend: .betterDisplay, betterDisplayUUID: nil),
            devices: [],
            availability: .discovering
        )
        #expect(!state.canSelectDisplay)
        #expect(!state.showsDisplayPicker)
    }

    @Test
    func anUnknownCatalogDoesNotClaimTheSavedDisplayIsDisconnected() {
        let state = BetterDisplayVolumeSettingsState(
            outputUID: "audio-a",
            configuration: ExternalVolumeConfiguration(
                backend: .betterDisplay, betterDisplayUUID: "display-a"
            ),
            devices: [],
            availability: .discovering
        )
        #expect(!state.pickerOptions.contains(.unavailable(uuid: "display-a")))
    }

    @Test
    func readyRequiresMatchingOutputDisplayAndWritableReadback() {
        let catalog = [BetterDisplayDevice(uuid: "display-a", name: "Desk")]
        func state(output: String?, display: String?, writable: Bool) -> BetterDisplayVolumeSettingsState {
            BetterDisplayVolumeSettingsState(
                outputUID: "audio-a",
                configuration: ExternalVolumeConfiguration(
                    backend: .betterDisplay, betterDisplayUUID: "display-a"
                ),
                devices: catalog,
                availability: .available,
                runtime: BetterDisplayCatalogUpdate(
                    devices: catalog, availability: .available, isCatalogLoaded: true,
                    outputUID: output, displayUUID: display, canSetVolume: writable
                )
            )
        }
        #expect(state(output: "audio-a", display: "display-a", writable: true).setupStatus == .ready)
        #expect(state(output: "audio-a", display: "display-a", writable: false).setupStatus == .checking)
        #expect(state(output: "audio-a", display: "display-b", writable: true).setupStatus == .checking)
        #expect(state(output: "audio-b", display: "display-a", writable: true).setupStatus == .discovering)
        #expect(state(output: nil, display: nil, writable: true).setupStatus == .checking)
    }

    @Test
    func nativeControlHidesConnectionControlsAndOverridesStaleFailures() {
        let state = BetterDisplayVolumeSettingsState(
            outputUID: "audio-a",
            configuration: ExternalVolumeConfiguration(backend: .betterDisplay, betterDisplayUUID: nil),
            devices: [], availability: .appAbsent, usesNativeVolumeControl: true
        )
        #expect(state.setupStatus == .native)
        #expect(!state.showsConnectionControls)
        #expect(!state.canSelectDisplay)
    }

    @Test
    func unknownEmptyAndMissingCatalogsHaveDistinctRecoveryStates() {
        var state = BetterDisplayVolumeSettingsState(
            outputUID: "audio-a",
            configuration: ExternalVolumeConfiguration(backend: .betterDisplay, betterDisplayUUID: nil),
            devices: [], availability: .discovering
        )
        #expect(state.setupStatus == .discovering)
        state = BetterDisplayVolumeSettingsState(
            outputUID: "audio-a", configuration: state.configuration,
            devices: [], availability: .deviceUnassociated
        )
        #expect(state.setupStatus == .noDisplays)
        #expect(!state.canSelectDisplay)
        let missing = BetterDisplayVolumeSettingsState(
            outputUID: "audio-a",
            configuration: ExternalVolumeConfiguration(backend: .betterDisplay, betterDisplayUUID: "gone"),
            devices: [], availability: .deviceUnassociated
        )
        #expect(missing.setupStatus == .missingDisplay)
        #expect(missing.pickerOptions.contains(.unavailable(uuid: "gone")))
    }

    @Test
    func duplicateNamesAreDisambiguatedWithoutChangingUUIDBindings() {
        let state = BetterDisplayVolumeSettingsState(
            outputUID: "audio-a",
            configuration: ExternalVolumeConfiguration(backend: .betterDisplay, betterDisplayUUID: nil),
            devices: [
                BetterDisplayDevice(uuid: "12345678-first", name: "Desk"),
                BetterDisplayDevice(uuid: "87654321-second", name: "Desk"),
                BetterDisplayDevice(uuid: "third", name: "Studio")
            ],
            availability: .deviceUnassociated
        )
        #expect(state.deviceLabel(uuid: "12345678-first", name: "Desk") == "Desk · 12345678")
        #expect(state.deviceLabel(uuid: "third", name: "Studio") == "Studio")
        #expect(state.pickerOptions.map(\.uuid) == [nil, "12345678-first", "87654321-second", "third"])
        #expect(state.setupStatus == .chooseDisplay)
    }
}
