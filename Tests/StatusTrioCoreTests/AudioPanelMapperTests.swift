import AudioToolbox
import XCTest
@testable import StatusTrioCore

@MainActor
final class AudioPanelMapperTests: XCTestCase {
    func testInputRowsKeepStableIdentityAndDisambiguateDuplicateNames() {
        let localization = makeLocalization(.english)
        let first = AudioInputDevice(id: AudioDeviceID(1), uid: "first", name: "Studio Mic")
        let second = AudioInputDevice(id: AudioDeviceID(2), uid: "second", name: "Studio Mic")
        let status = makeInputStatus(devices: [first, second], defaultDeviceID: second.id)

        let state = AudioPanelMapper.input(status, localization: localization)

        XCTAssertEqual(state.rows.map(\.key.id), [2, 1])
        XCTAssertEqual(Set(state.rows.map(\.key)).count, 2)
        XCTAssertEqual(state.rows.map(\.name), ["Studio Mic", "Studio Mic"])
        XCTAssertTrue(state.rows.allSatisfy { $0.accessibilityLabel.contains("Studio Mic") })
        XCTAssertTrue(state.rows[0].selected)
        XCTAssertFalse(state.rows[1].selected)
    }

    func testInputKeepsBusyAndCapabilitiesAsSeparateControlRules() {
        let localization = makeLocalization(.english)
        let busyButCapable = AudioPanelMapper.input(
            makeInputStatus(
                defaultDeviceID: AudioDeviceID(1),
                scalar: 0.4,
                canSetVolume: true,
                muteState: .unmuted,
                canSetMute: true,
                isBusy: true
            ),
            localization: localization
        )
        let readOnlyGain = AudioPanelMapper.input(
            makeInputStatus(
                defaultDeviceID: AudioDeviceID(1),
                scalar: 0.4,
                canSetVolume: false,
                muteState: .unmuted,
                canSetMute: true
            ),
            localization: localization
        )
        let muteUnavailable = AudioPanelMapper.input(
            makeInputStatus(
                defaultDeviceID: AudioDeviceID(1),
                scalar: 0.4,
                canSetVolume: true,
                muteState: .unmuted,
                canSetMute: false
            ),
            localization: localization
        )

        XCTAssertTrue(busyButCapable.isBusy)
        XCTAssertFalse(busyButCapable.canAdjust)
        XCTAssertFalse(busyButCapable.canMute)
        XCTAssertFalse(readOnlyGain.canAdjust)
        XCTAssertTrue(readOnlyGain.canMute)
        XCTAssertTrue(muteUnavailable.canAdjust)
        XCTAssertFalse(muteUnavailable.canMute)
    }

    func testInputPartialMuteAndUnavailableVolumeRemainVisibleWithoutInventedZero() {
        let localization = makeLocalization(.english)
        let partial = AudioPanelMapper.input(
            makeInputStatus(
                devices: [AudioInputDevice(id: AudioDeviceID(1), uid: "mic", name: "Mic")],
                defaultDeviceID: AudioDeviceID(1),
                scalar: nil,
                canSetVolume: true,
                muteState: .partial,
                canSetMute: true,
                isDefaultInputInUse: nil,
                error: .volumeFailed
            ),
            localization: localization
        )

        XCTAssertEqual(partial.scalar, nil)
        XCTAssertEqual(partial.percentageText, "—")
        XCTAssertFalse(partial.canAdjust)
        XCTAssertTrue(partial.canMute)
        XCTAssertEqual(partial.muteSymbol, "mic.fill")
        XCTAssertEqual(partial.muteTint, .secondary)
        XCTAssertEqual(partial.usageText, nil)
        XCTAssertEqual(partial.errorText, localization.string(.audioInputVolumeFailed))
        XCTAssertTrue(partial.showsDeviceList)
        XCTAssertEqual(partial.rows.map(\.name), ["Mic"])
    }

    func testInputUseMarkerAndErrorAreLocalizedInPanelState() {
        let english = makeLocalization(.english)
        let german = makeLocalization(.german)
        let status = makeInputStatus(
            devices: [AudioInputDevice(id: AudioDeviceID(1), uid: "mic", name: "Mic")],
            defaultDeviceID: AudioDeviceID(1),
            isDefaultInputInUse: true,
            error: .switchFailed
        )

        let englishState = AudioPanelMapper.input(status, localization: english)
        let germanState = AudioPanelMapper.input(status, localization: german)

        XCTAssertEqual(englishState.usageText, "In Use")
        XCTAssertEqual(englishState.errorText, "Could not switch input device.")
        XCTAssertEqual(germanState.usageText, "In Benutzung")
        XCTAssertEqual(germanState.errorText, "Eingabegerät konnte nicht gewechselt werden.")
    }

    func testVolumeUnavailableScalarStaysUnavailableAndControlsRespectCapabilities() {
        let localization = makeLocalization(.english)
        let status = VolumeStatus(
            scalar: nil,
            isMuted: false,
            deviceName: nil,
            canSetVolume: true,
            canMute: false
        )

        let state = AudioPanelMapper.volume(
            status,
            controllerAvailable: true,
            localization: localization
        )

        XCTAssertNil(state.scalar)
        XCTAssertEqual(state.percentageText, "—")
        XCTAssertFalse(state.canAdjust)
        XCTAssertFalse(state.canMute)
        XCTAssertEqual(state.summary.title, "No default output device")
    }

    func testOutputSummaryRejectsCachedIconWhenLiveDeviceNameHasChanged() {
        let localization = makeLocalization(.english)
        let cachedDevice = AudioOutputDevice(
            id: AudioDeviceID(42),
            name: "Cached headphones",
            uid: "headphones",
            isCurrent: true,
            transport: .bluetooth
        )
        let state = AudioPanelMapper.volume(
            VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: "Renamed output",
                outputDevices: [cachedDevice],
                canSetVolume: true,
                canMute: true
            ),
            controllerAvailable: true,
            localization: localization
        )

        XCTAssertEqual(state.summary.title, "Renamed output")
        XCTAssertEqual(
            state.summary.symbol,
            .symbol(name: "speaker.wave.2.fill", variableValue: nil, fallback: nil)
        )
    }

    func testOutputSummaryUsesStaticSpeakerFallbackWithoutDeviceMetadata() {
        let localization = makeLocalization(.english)
        let state = AudioPanelMapper.volume(
            VolumeStatus(
                scalar: 0.2,
                isMuted: true,
                deviceName: "Live output",
                outputDevices: [],
                canSetVolume: true,
                canMute: true
            ),
            controllerAvailable: true,
            localization: localization
        )

        XCTAssertEqual(
            state.summary.symbol,
            .symbol(name: "speaker.wave.2.fill", variableValue: nil, fallback: nil)
        )
        XCTAssertEqual(state.muteSymbol, "speaker.slash.fill")
    }

    func testOutputSummaryUsesMatchingCurrentDeviceIcon() {
        let localization = makeLocalization(.english)
        let device = AudioOutputDevice(
            id: AudioDeviceID(43),
            name: "Bluetooth Headphones",
            uid: "headphones",
            isCurrent: true,
            transport: .bluetooth
        )
        let state = AudioPanelMapper.volume(
            VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: device.name,
                outputDevices: [device],
                canSetVolume: true,
                canMute: true
            ),
            controllerAvailable: true,
            localization: localization
        )

        XCTAssertNotEqual(
            state.summary.symbol,
            .symbol(name: "speaker.wave.2.fill", variableValue: nil, fallback: nil)
        )
    }

    func testOutputRowsUseStableUIDKeysOrderingAndLocalExpansionProjection() {
        let localization = makeLocalization(.english)
        let first = AudioOutputDevice(
            id: AudioDeviceID(1),
            name: "Studio Speaker",
            uid: "first",
            isCurrent: false
        )
        let second = AudioOutputDevice(
            id: AudioDeviceID(2),
            name: "Studio Speaker",
            uid: "second",
            isCurrent: true
        )
        let third = AudioOutputDevice(
            id: AudioDeviceID(3),
            name: nil,
            uid: nil,
            isCurrent: false
        )
        let status = VolumeStatus(
            scalar: 0.5,
            isMuted: false,
            deviceName: nil,
            currentDevice: second,
            outputDevices: [first, second, third],
            canSetVolume: true,
            canMute: true
        )

        let state = AudioPanelMapper.volume(
            status,
            controllerAvailable: true,
            deviceList: AudioOutputListPreferences(order: ["second"], visibleLimit: 1),
            localization: localization
        )

        XCTAssertEqual(state.rows.map(\.key), [
            PanelAudioDeviceID(id: 2, uid: "second"),
            PanelAudioDeviceID(id: 1, uid: "first"),
            PanelAudioDeviceID(id: 3, uid: nil)
        ])
        XCTAssertEqual(Set(state.rows.map(\.key)).count, 3)
        XCTAssertEqual(state.visibleRows(expanded: false).map(\.key.id), [2])
        XCTAssertEqual(state.visibleRows(expanded: true).map(\.key.id), [2, 1, 3])
        XCTAssertTrue(state.hasHiddenRows)
        XCTAssertTrue(state.rows[0].selected)
        XCTAssertNotEqual(state.rows[0].accessibilityLabel, state.rows[1].accessibilityLabel)
        XCTAssertEqual(state.rows[2].name, "Unknown output device")
    }

    private func makeLocalization(_ language: AppLanguage) -> Localization {
        let suiteName = "AudioPanelMapperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        return localization
    }

    private func makeInputStatus(
        devices: [AudioInputDevice] = [],
        defaultDeviceID: AudioDeviceID? = nil,
        scalar: Double? = 0.4,
        canSetVolume: Bool = true,
        muteState: AudioInputMuteState? = .unmuted,
        canSetMute: Bool = true,
        isBusy: Bool = false,
        isDefaultInputInUse: Bool? = false,
        error: AudioInputError? = nil
    ) -> AudioInputStatus {
        AudioInputStatus(
            devices: devices,
            defaultDeviceID: defaultDeviceID,
            deviceName: nil,
            scalar: scalar,
            canSetVolume: canSetVolume,
            muteState: muteState,
            canSetMute: canSetMute,
            isRefreshing: false,
            isBusy: isBusy,
            error: error,
            isDefaultInputInUse: isDefaultInputInUse
        )
    }
}
