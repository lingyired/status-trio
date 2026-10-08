import CoreAudio
import XCTest
@testable import StatusTrioCore

final class AudioInputPresentationTests: XCTestCase {
    func testOrderedPlacesCurrentDeviceFirstAndUsesLocaleAndIDForRemainingRows() {
        let builtIn = AudioInputDevice(id: AudioDeviceID(12), uid: "built-in", name: "Built-in")
        let usb = AudioInputDevice(id: AudioDeviceID(4), uid: "usb", name: "USB")
        let lowerAlpha = AudioInputDevice(id: AudioDeviceID(8), uid: "lower", name: "alpha")
        let upperAlpha = AudioInputDevice(id: AudioDeviceID(2), uid: "upper", name: "Alpha")

        let rows = AudioInputPresentation.ordered(
            [builtIn, usb, lowerAlpha, upperAlpha],
            currentID: usb.id,
            locale: Locale(identifier: "zh_CN"),
            unknownName: "未知输入设备"
        )

        XCTAssertEqual(rows.map(\.id), [usb.id, upperAlpha.id, lowerAlpha.id, builtIn.id])
    }

    func testOrderedUsesUnknownNameAndIDForUnnamedDevices() {
        let usb = AudioInputDevice(id: AudioDeviceID(9), uid: "usb", name: "USB Mic")
        let unnamedLater = AudioInputDevice(id: AudioDeviceID(8), uid: nil, name: "")
        let unnamedFirst = AudioInputDevice(id: AudioDeviceID(3), uid: "no-name", name: nil)

        let rows = AudioInputPresentation.ordered(
            [usb, unnamedLater, unnamedFirst],
            currentID: nil,
            locale: Locale(identifier: "en_US"),
            unknownName: "Unknown input device"
        )

        XCTAssertEqual(rows.map(\.id), [unnamedFirst.id, unnamedLater.id, usb.id])
    }

    func testOrderedPreservesLongNamesForTheViewToTruncate() {
        let longName = String(repeating: "Studio microphone ", count: 12)
        let device = AudioInputDevice(id: AudioDeviceID(15), uid: "studio", name: longName)

        let rows = AudioInputPresentation.ordered(
            [device],
            currentID: nil,
            locale: Locale(identifier: "en_US"),
            unknownName: "Unknown input device"
        )

        XCTAssertEqual(rows.first?.name, longName)
    }

    func testFailuresMapToTheirLocalizedBannerKeys() {
        let cases: [(AudioInputError, LocalizationKey)] = [
            (.refreshFailed, .audioInputRefreshFailed),
            (.switchFailed, .audioInputSwitchFailed),
            (.volumeFailed, .audioInputVolumeFailed),
            (.muteFailed, .audioInputMuteFailed),
            (.timedOut, .audioInputTimedOut)
        ]

        for (error, key) in cases {
            XCTAssertEqual(AudioInputPresentation.errorLocalizationKey(for: error), key)
        }
    }

    func testInputUseBadgeAppearsOnlyForAConfirmedActiveDefaultInput() {
        XCTAssertFalse(AudioInputPresentation(status: makeStatus(isDefaultInputInUse: nil)).isDefaultInputInUse)
        XCTAssertFalse(AudioInputPresentation(status: makeStatus(isDefaultInputInUse: false)).isDefaultInputInUse)
        XCTAssertTrue(AudioInputPresentation(status: makeStatus(isDefaultInputInUse: true)).isDefaultInputInUse)
    }

    func testAccessibilityPositionIsAddedForDuplicateAndUnnamedDevices() {
        let first = AudioInputDevice(id: AudioDeviceID(1), uid: "first", name: "Studio Mic")
        let second = AudioInputDevice(id: AudioDeviceID(2), uid: "second", name: "Studio Mic")
        let unnamed = AudioInputDevice(id: AudioDeviceID(3), uid: nil, name: "  ")
        let devices = [first, second, unnamed]
        let locale = Locale(identifier: "en_US")

        XCTAssertTrue(AudioInputPresentation.needsDevicePosition(
            for: first,
            among: devices,
            unknownName: "Unknown input device",
            locale: locale
        ))
        XCTAssertTrue(AudioInputPresentation.needsDevicePosition(
            for: unnamed,
            among: devices,
            unknownName: "Unknown input device",
            locale: locale
        ))
        XCTAssertFalse(AudioInputPresentation.needsDevicePosition(
            for: AudioInputDevice(id: AudioDeviceID(4), uid: "solo", name: "Solo Mic"),
            among: devices,
            unknownName: "Unknown input device",
            locale: locale
        ))
    }

    func testAccessibilityLabelCombinesLocalizedNamePositionAndCurrentMarker() {
        let label = AudioInputPresentation.deviceAccessibilityLabel(
            name: "Unknown input device",
            position: "Input device 2",
            current: "Current"
        ) { first, second in
            "\(first), \(second)"
        }

        XCTAssertEqual(label, "Unknown input device, Input device 2, Current")
    }

    func testSharedNameDisambiguationAlsoFindsDuplicateOutputDeviceNames() {
        let duplicate = AudioInputPresentation.needsDevicePosition(
            name: "Studio Speaker",
            id: AudioDeviceID(1),
            among: [
                (id: AudioDeviceID(1), name: "Studio Speaker"),
                (id: AudioDeviceID(2), name: " studio speaker ")
            ],
            unknownName: "Unknown output device",
            locale: Locale(identifier: "en_US")
        )
        let unnamed = AudioInputPresentation.needsDevicePosition(
            name: nil,
            id: AudioDeviceID(3),
            among: [(id: AudioDeviceID(3), name: nil)],
            unknownName: "Unknown output device",
            locale: Locale(identifier: "en_US")
        )

        XCTAssertTrue(duplicate)
        XCTAssertTrue(unnamed)
    }

    func testDeviceListShowsWithoutDefaultAndForASingleDevice() {
        let device = AudioInputDevice(id: AudioDeviceID(7), uid: "built-in", name: "Built-in Microphone")
        let noDefault = makeStatus(devices: [device])

        XCTAssertTrue(AudioInputPresentation(status: noDefault).showsDeviceList)
        XCTAssertFalse(AudioInputPresentation(status: .empty).showsDeviceList)
    }

    func testUnsupportedAndBusyControlsAreDisabled() {
        let noVolumeSupport = makeStatus(
            defaultDeviceID: AudioDeviceID(1),
            scalar: 0.4,
            canSetVolume: false
        )
        let noMuteSupport = makeStatus(
            defaultDeviceID: AudioDeviceID(1),
            muteState: .unmuted,
            canSetMute: false
        )
        let busy = makeStatus(
            defaultDeviceID: AudioDeviceID(1),
            scalar: 0.4,
            canSetVolume: true,
            muteState: .unmuted,
            canSetMute: true,
            isBusy: true
        )

        XCTAssertFalse(AudioInputPresentation(status: noVolumeSupport).volumeEnabled)
        XCTAssertFalse(AudioInputPresentation(status: noMuteSupport).muteEnabled)
        XCTAssertFalse(AudioInputPresentation(status: busy).volumeEnabled)
        XCTAssertFalse(AudioInputPresentation(status: busy).muteEnabled)
    }

    func testMuteTargetTreatsPartialMuteAsNeitherMutedNorUnmuted() {
        XCTAssertTrue(AudioInputPresentation(status: makeStatus(muteState: .unmuted)).nextMuteValue)
        XCTAssertFalse(AudioInputPresentation(status: makeStatus(muteState: .muted)).nextMuteValue)
        XCTAssertTrue(AudioInputPresentation(status: makeStatus(muteState: .partial)).nextMuteValue)
    }

    func testVolumeAccessibilityValueUsesLocaleAndDashForUnknownValues() {
        let locale = Locale(identifier: "fr_FR")
        let known = AudioInputPresentation(
            status: makeStatus(scalar: 0.42, canSetVolume: true),
            locale: locale
        )
        let unknown = AudioInputPresentation(
            status: makeStatus(scalar: nil, canSetVolume: false),
            locale: locale
        )

        XCTAssertEqual(
            known.volumeAccessibilityValue,
            0.42.formatted(.percent.precision(.fractionLength(0)).locale(locale))
        )
        XCTAssertEqual(unknown.volumeAccessibilityValue, "—")
    }

    func testOutOfRangeVolumeReadbackIsUnavailableRatherThanClampedToAnEndpoint() {
        let locale = Locale(identifier: "en_US")

        for scalar in [-0.1, 1.1] {
            let presentation = AudioInputPresentation(
                status: makeStatus(scalar: scalar, canSetVolume: true),
                locale: locale
            )

            XCTAssertEqual(presentation.visibleVolumeValue, "—", "scalar=\(scalar)")
            XCTAssertEqual(presentation.volumeAccessibilityValue, "—", "scalar=\(scalar)")
            XCTAssertFalse(presentation.volumeEnabled, "scalar=\(scalar)")
        }
    }

    func testVisibleVolumeValueShowsReadableReadOnlyGainAndDashWhenUnreadable() {
        let locale = Locale(identifier: "en_US")
        let readOnly = AudioInputPresentation(
            status: makeStatus(scalar: 0.42, canSetVolume: false),
            locale: locale
        )
        let unreadable = AudioInputPresentation(
            status: makeStatus(scalar: nil, canSetVolume: false),
            locale: locale
        )

        XCTAssertEqual(
            readOnly.visibleVolumeValue,
            0.42.formatted(.percent.precision(.fractionLength(0)).locale(locale))
        )
        XCTAssertEqual(unreadable.visibleVolumeValue, "—")
    }

    func testVolumeDraftAccessibilityValueHidesDragValueWhenReadbackBecomesUnavailable() {
        let locale = Locale(identifier: "en_US")
        var draft = AudioInputVolumeDraft()
        draft.receiveSystemScalar(0.4)
        draft.setEditing(true)
        draft.setSliderValue(0.8, systemScalar: 0.4) { _ in }

        XCTAssertEqual(
            draft.accessibilityValue(systemScalar: 0.4, locale: locale),
            0.8.formatted(.percent.precision(.fractionLength(0)).locale(locale))
        )

        for scalar in [nil, -0.1, 1.1] as [Double?] {
            draft.receiveSystemScalar(scalar)
            XCTAssertEqual(
                draft.accessibilityValue(systemScalar: scalar, locale: locale),
                "—",
                "scalar=\(String(describing: scalar)) must not expose the in-progress draft"
            )
        }
    }

    func testVolumeDraftReconcilesDifferingSystemReadbackWhenDragEnds() {
        var draft = AudioInputVolumeDraft()
        draft.receiveSystemScalar(0.2)
        draft.setEditing(true)
        draft.setSliderValue(0.8, systemScalar: 0.2) { _ in }

        draft.receiveSystemScalar(0.4)
        XCTAssertEqual(draft.value, 0.8, accuracy: 0.0001)

        draft.setEditing(false)
        XCTAssertFalse(draft.isEditing)
        XCTAssertEqual(draft.value, 0.4, accuracy: 0.0001)

        // A delayed slider setter after mouse-up must not restore the rejected draft.
        draft.setSliderValue(0.8, systemScalar: 0.4) { _ in }
        XCTAssertEqual(draft.value, 0.4, accuracy: 0.0001)
    }

    func testVolumeDraftDispatchesOnlyAcceptedEditsThroughSliderCallback() {
        var draft = AudioInputVolumeDraft()
        var requests: [Double] = []
        draft.receiveSystemScalar(0.2)
        draft.setEditing(true)

        draft.setSliderValue(0.8, systemScalar: 0.2) { requests.append($0) }
        XCTAssertEqual(requests, [0.8])

        draft.receiveSystemScalar(0.4)
        draft.setEditing(false)
        XCTAssertEqual(draft.value, 0.4, accuracy: 0.0001)

        // The same callback path used by the Binding must not re-submit a stale value.
        draft.setSliderValue(0.8, systemScalar: 0.4) { requests.append($0) }
        XCTAssertEqual(draft.value, 0.4, accuracy: 0.0001)
        XCTAssertEqual(requests, [0.8])
    }

    func testVolumeDraftResetsWhenInputDeviceChangesAtTheSameScalar() {
        var draft = AudioInputVolumeDraft()
        let firstDevice = PanelAudioInputIdentity(rawValue: 11)
        let secondDevice = PanelAudioInputIdentity(rawValue: 22)
        draft.receiveSystemState(deviceIdentity: firstDevice, scalar: 0.55)
        draft.setEditing(true)
        draft.setSliderValue(0.9, systemScalar: 0.55) { _ in }

        draft.receiveSystemState(deviceIdentity: secondDevice, scalar: 0.55)

        XCTAssertFalse(draft.isEditing)
        XCTAssertEqual(draft.value, 0.55, accuracy: 0.0001)
    }

    func testVolumeDraftResetsToNewInputScalarWhenDeviceChangesDuringEditing() {
        var draft = AudioInputVolumeDraft()
        draft.receiveSystemState(deviceIdentity: PanelAudioInputIdentity(rawValue: 11), scalar: 0.55)
        draft.setEditing(true)
        draft.setSliderValue(0.9, systemScalar: 0.55) { _ in }

        draft.receiveSystemState(deviceIdentity: PanelAudioInputIdentity(rawValue: 22), scalar: 0.31)

        XCTAssertFalse(draft.isEditing)
        XCTAssertEqual(draft.value, 0.31, accuracy: 0.0001)
    }

    func testVolumeDraftKeepsActiveDraftForSameInputIdentityScalarUpdates() {
        var draft = AudioInputVolumeDraft()
        let device = PanelAudioInputIdentity(rawValue: 11)
        draft.receiveSystemState(deviceIdentity: device, scalar: 0.55)
        draft.setEditing(true)
        draft.setSliderValue(0.9, systemScalar: 0.55) { _ in }

        draft.receiveSystemState(deviceIdentity: device, scalar: 0.31)

        XCTAssertTrue(draft.isEditing)
        XCTAssertEqual(draft.value, 0.9, accuracy: 0.0001)
    }

    private func makeStatus(
        devices: [AudioInputDevice] = [],
        defaultDeviceID: AudioDeviceID? = nil,
        scalar: Double? = nil,
        canSetVolume: Bool = false,
        muteState: AudioInputMuteState? = nil,
        canSetMute: Bool = false,
        isRefreshing: Bool = false,
        isBusy: Bool = false,
        error: AudioInputError? = nil,
        isDefaultInputInUse: Bool? = nil
    ) -> AudioInputStatus {
        AudioInputStatus(
            devices: devices,
            defaultDeviceID: defaultDeviceID,
            deviceName: nil,
            scalar: scalar,
            canSetVolume: canSetVolume,
            muteState: muteState,
            canSetMute: canSetMute,
            isRefreshing: isRefreshing,
            isBusy: isBusy,
            error: error,
            isDefaultInputInUse: isDefaultInputInUse
        )
    }
}
