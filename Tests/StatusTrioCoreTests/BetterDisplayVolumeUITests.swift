import AudioToolbox
import XCTest
@testable import StatusTrioCore

@MainActor
final class BetterDisplayVolumeUITests: XCTestCase {
    private let betterDisplayLocalizationKeys: [LocalizationKey] = [
        .settingsAudioExternalVolumeTitle,
        .settingsAudioExternalVolumeControlMethod,
        .settingsAudioExternalVolumeControlMethodDescription,
        .settingsAudioExternalVolumeExistingBehavior,
        .settingsAudioExternalVolumeBetterDisplay,
        .settingsAudioExternalVolumeDisplay,
        .settingsAudioExternalVolumeDisplayDescription,
        .settingsAudioExternalVolumeUnassociated,
        .settingsAudioExternalVolumeUnavailableDisplay,
        .settingsAudioExternalVolumeRefresh,
        .settingsAudioExternalVolumeRequirements,
        .settingsAudioExternalVolumeFootnote,
        .settingsAudioExternalVolumeNoStableOutput,
        .settingsAudioExternalVolumeStatusReady,
        .settingsAudioExternalVolumeStatusIdle,
        .settingsAudioExternalVolumeStatusBusy,
        .settingsAudioExternalVolumeStatusUpdating,
        .settingsAudioExternalVolumeStatusAppAbsent,
        .settingsAudioExternalVolumeStatusUnresponsive,
        .settingsAudioExternalVolumeStatusInvalidResponse,
        .settingsAudioExternalVolumeStatusRequestFailed,
        .settingsAudioExternalVolumeStatusChooseDisplay,
        .settingsAudioExternalVolumeStatusNotConfirmed,
        .volumeMuteUnavailable
    ]

    func testProgrammaticScalarSynchronizationNeverEmitsUserActions() {
        let identity = VolumeControlInteractionIdentity(
            output: PanelAudioDeviceID(id: 41, uid: "audio-a"),
            configuration: .default
        )
        var emittedScalars: [Double] = []
        var finishCount = 0
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: { finishCount += 1 }
        )

        // The same action sink used by user input is installed while
        // synchronization runs. Programmatic reads must not reach it.
        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.2,
            canAdjust: true
        )
        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.7,
            canAdjust: true
        )

        XCTAssertEqual(interaction.value, 0.7, accuracy: 0.000_001)
        XCTAssertTrue(emittedScalars.isEmpty)
        XCTAssertEqual(finishCount, 0)
    }

    func testUnmanagedSliderBindingUpdateDoesNotRemainEditing() {
        let identity = VolumeControlInteractionIdentity(
            output: PanelAudioDeviceID(id: 40, uid: "audio-unmanaged"),
            configuration: .default
        )
        var emittedScalars: [Double] = []
        var finishCount = 0
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: { finishCount += 1 }
        )

        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.2,
            canAdjust: true
        )
        interaction.setSliderValue(
            0.6,
            identity: identity,
            canAdjust: true
        )

        XCTAssertFalse(interaction.isEditing)
        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.35,
            canAdjust: true
        )

        XCTAssertEqual(interaction.value, 0.35, accuracy: 0.000_001)
        XCTAssertEqual(emittedScalars, [0.6])
        interaction.endEditing(identity: identity)
        XCTAssertEqual(finishCount, 0)
    }

    func testExplicitEditingAfterSystemSyncOwnsDragUntilRelease() {
        let identity = VolumeControlInteractionIdentity(
            output: PanelAudioDeviceID(id: 41, uid: "audio-owned"),
            configuration: .default
        )
        var emittedScalars: [Double] = []
        var finishCount = 0
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: { finishCount += 1 }
        )

        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.2,
            canAdjust: true
        )
        interaction.beginEditing()
        interaction.setSliderValue(
            0.65,
            identity: identity,
            canAdjust: true
        )
        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.3,
            canAdjust: true
        )

        XCTAssertTrue(interaction.isEditing)
        XCTAssertEqual(interaction.value, 0.65, accuracy: 0.000_001)

        interaction.endEditing(identity: identity)
        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.4,
            canAdjust: true
        )

        XCTAssertFalse(interaction.isEditing)
        XCTAssertEqual(interaction.value, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(emittedScalars, [0.65])
        XCTAssertEqual(finishCount, 1)
    }

    func testUserScalarSetterGuardsCapabilityAndEmitsChangedValueOnce() {
        let identity = VolumeControlInteractionIdentity(
            output: PanelAudioDeviceID(id: 42, uid: "audio-b"),
            configuration: .default
        )
        var emittedScalars: [Double] = []
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: {}
        )
        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.4,
            canAdjust: true
        )

        interaction.setSliderValue(
            0.8,
            identity: identity,
            canAdjust: false
        )
        XCTAssertTrue(emittedScalars.isEmpty)
        XCTAssertEqual(interaction.value, 0.4, accuracy: 0.000_001)

        interaction.setSliderValue(
            0.731,
            identity: identity,
            canAdjust: true
        )
        interaction.setSliderValue(
            0.731,
            identity: identity,
            canAdjust: true
        )

        XCTAssertEqual(emittedScalars.count, 1)
        XCTAssertEqual(emittedScalars[0], 0.731, accuracy: 0.000_001)
        XCTAssertEqual(interaction.value, 0.731, accuracy: 0.000_001)
    }

    func testReleaseFlushesOnceAndSelectionChangeDropsStaleDraftAndAction() {
        let first = PanelAudioDeviceID(id: 51, uid: "audio-a")
        let second = PanelAudioDeviceID(id: 52, uid: "audio-b")
        let firstIdentity = VolumeControlInteractionIdentity(
            output: first,
            configuration: .default
        )
        let secondIdentity = VolumeControlInteractionIdentity(
            output: second,
            configuration: .default
        )
        var emittedScalars: [Double] = []
        var finishCount = 0
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: { finishCount += 1 }
        )

        interaction.receiveSystemState(
            identity: firstIdentity,
            scalar: 0.5,
            canAdjust: true
        )
        interaction.beginEditing()
        interaction.setSliderValue(
            0.8,
            identity: firstIdentity,
            canAdjust: true
        )

        // A live read does not overwrite an in-progress same-output edit.
        interaction.receiveSystemState(
            identity: firstIdentity,
            scalar: 0.5,
            canAdjust: true
        )
        XCTAssertEqual(interaction.value, 0.8, accuracy: 0.000_001)

        // Selection wins even when the two outputs report the same scalar.
        interaction.receiveSystemState(
            identity: secondIdentity,
            scalar: 0.5,
            canAdjust: true
        )
        XCTAssertEqual(interaction.value, 0.5, accuracy: 0.000_001)
        XCTAssertFalse(interaction.isEditing)

        // A late setter or release from the old identity is inert.
        interaction.setSliderValue(
            0.9,
            identity: firstIdentity,
            canAdjust: true
        )
        interaction.endEditing(identity: firstIdentity)
        XCTAssertEqual(emittedScalars, [0.8])
        XCTAssertEqual(finishCount, 0)

        interaction.setSliderValue(
            0.9,
            identity: secondIdentity,
            canAdjust: true
        )
        interaction.endEditing(identity: secondIdentity)

        // A transition while the old gesture was active requires a fresh
        // pointer/edit boundary before the new output can accept input.
        interaction.beginEditing()
        interaction.setSliderValue(
            0.9,
            identity: secondIdentity,
            canAdjust: true
        )
        interaction.endEditing(identity: secondIdentity)

        XCTAssertEqual(emittedScalars, [0.8, 0.9])
        XCTAssertEqual(finishCount, 1)
    }

    func testCapabilityOrScalarLossMidDragCannotFlushTheOldDraft() {
        let output = PanelAudioDeviceID(id: 53, uid: "audio-c")
        let identity = VolumeControlInteractionIdentity(
            output: output,
            configuration: .default
        )
        var emittedScalars: [Double] = []
        var finishCount = 0
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: { finishCount += 1 }
        )

        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.5,
            canAdjust: true
        )
        interaction.beginEditing()
        interaction.setSliderValue(
            0.8,
            identity: identity,
            canAdjust: true
        )
        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.5,
            canAdjust: false
        )

        XCTAssertEqual(interaction.value, 0.5, accuracy: 0.000_001)
        XCTAssertFalse(interaction.isEditing)
        interaction.endEditing(identity: identity)
        XCTAssertEqual(finishCount, 0)

        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.5,
            canAdjust: true
        )
        interaction.setSliderValue(
            0.7,
            identity: identity,
            canAdjust: true
        )
        interaction.endEditing(identity: identity)
        // The stale release consumed the interruption lock. The recovered
        // keyboard update is a fresh unmanaged edit and may finish once.
        XCTAssertEqual(finishCount, 1)

        interaction.beginEditing()
        interaction.setSliderValue(
            0.7,
            identity: identity,
            canAdjust: true
        )
        interaction.receiveSystemState(
            identity: identity,
            scalar: nil,
            canAdjust: false
        )

        XCTAssertEqual(interaction.value, 0, accuracy: 0.000_001)
        XCTAssertFalse(interaction.isEditing)
        interaction.setSliderValue(
            0.9,
            identity: identity,
            canAdjust: false
        )
        interaction.endEditing(identity: identity)

        XCTAssertEqual(emittedScalars, [0.8, 0.7])
        XCTAssertEqual(finishCount, 1)
    }

    func testBackendChangeAtTheSameOutputInvalidatesDraftInteraction() {
        let output = PanelAudioDeviceID(id: 54, uid: "audio-d")
        let direct = VolumeControlInteractionIdentity(
            output: output,
            configuration: .default
        )
        let betterDisplay = VolumeControlInteractionIdentity(
            output: output,
            configuration: ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: nil
            )
        )
        var emittedScalars: [Double] = []
        var finishCount = 0
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: { finishCount += 1 }
        )

        interaction.receiveSystemState(
            identity: direct,
            scalar: 0.5,
            canAdjust: true
        )
        interaction.beginEditing()
        interaction.setSliderValue(
            0.8,
            identity: direct,
            canAdjust: true
        )
        interaction.receiveSystemState(
            identity: betterDisplay,
            scalar: 0.5,
            canAdjust: false
        )

        XCTAssertEqual(interaction.value, 0.5, accuracy: 0.000_001)
        XCTAssertFalse(interaction.isEditing)
        interaction.setSliderValue(
            0.9,
            identity: direct,
            canAdjust: true
        )
        interaction.endEditing(identity: direct)

        XCTAssertEqual(emittedScalars, [0.8])
        XCTAssertEqual(finishCount, 0)
    }

    func testMapperPublishesOutputIdentityAndDisablesUnknownMute() {
        let localization = makeLocalization(.english)
        let configuration = ExternalVolumeConfiguration(
            backend: .betterDisplay,
            betterDisplayUUID: "display-a"
        )
        let output = AudioOutputDevice(
            id: 61,
            name: "External display",
            uid: "audio-display",
            isCurrent: true,
            transport: .displayPort
        )
        let state = AudioPanelMapper.volume(
            VolumeStatus(
                scalar: 0.4,
                isMuted: false,
                deviceName: output.name,
                currentDevice: output,
                outputDevices: [output],
                canSetVolume: true,
                canMute: true,
                muteState: .unknown
            ),
            controllerAvailable: true,
            externalVolumeConfiguration: configuration,
            localization: localization
        )
        var muteActions = 0

        XCTAssertEqual(
            state.outputIdentity,
            PanelAudioDeviceID(id: output.id, uid: output.uid)
        )
        XCTAssertEqual(
            state.interactionIdentity,
            VolumeControlInteractionIdentity(
                output: PanelAudioDeviceID(id: output.id, uid: output.uid),
                configuration: configuration
            )
        )
        XCTAssertEqual(state.muteState, .unknown)
        XCTAssertFalse(state.canMute)
        XCTAssertEqual(
            state.muteHelp,
            localization.string(.volumeMuteUnavailable)
        )
        VolumePanelActionGate.toggleMute(in: state) {
            muteActions += 1
        }
        XCTAssertEqual(muteActions, 0)

        let unsupported = AudioPanelMapper.volume(
            VolumeStatus(
                scalar: 0.4,
                isMuted: false,
                deviceName: output.name,
                currentDevice: output,
                outputDevices: [output],
                canSetVolume: true,
                canMute: false,
                muteState: .unmuted
            ),
            controllerAvailable: true,
            localization: localization
        )
        VolumePanelActionGate.toggleMute(in: unsupported) {
            muteActions += 1
        }
        XCTAssertEqual(muteActions, 0)

        let supported = AudioPanelMapper.volume(
            VolumeStatus(
                scalar: 0.4,
                isMuted: false,
                deviceName: output.name,
                currentDevice: output,
                outputDevices: [output],
                canSetVolume: true,
                canMute: true,
                muteState: .unmuted
            ),
            controllerAvailable: true,
            localization: localization
        )
        VolumePanelActionGate.toggleMute(in: supported) {
            muteActions += 1
        }
        XCTAssertEqual(muteActions, 1)
    }

    func testExternalVolumeSettingsWriteOnlyNormalizedCurrentOutputUID() {
        var writtenConfigurations: [ExternalVolumeConfiguration] = []
        var writtenUIDs: [String] = []
        let recordWrite: (ExternalVolumeConfiguration, String) -> Void = {
            writtenConfigurations.append($0)
            writtenUIDs.append($1)
        }

        let current = BetterDisplayVolumeSettingsState(
            outputUID: "  audio-benq  ",
            configuration: .default,
            devices: [],
            availability: .idle
        )
        BetterDisplayVolumeSettingsActions(
            state: current,
            setConfiguration: recordWrite,
            refresh: {}
        ).setBackend(.betterDisplay)

        XCTAssertEqual(writtenUIDs, ["audio-benq"])
        XCTAssertEqual(
            writtenConfigurations,
            [
                ExternalVolumeConfiguration(
                    backend: .betterDisplay,
                    betterDisplayUUID: nil
                )
            ]
        )

        writtenConfigurations.removeAll()
        writtenUIDs.removeAll()
        let selected = BetterDisplayVolumeSettingsState(
            outputUID: "audio-benq",
            configuration: ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: "display-a"
            ),
            devices: [],
            availability: .available
        )
        BetterDisplayVolumeSettingsActions(
            state: selected,
            setConfiguration: recordWrite,
            refresh: {}
        ).setBackend(.directDDC)

        XCTAssertEqual(writtenUIDs, ["audio-benq"])
        XCTAssertEqual(writtenConfigurations, [.default])

        let invalidOutputUIDs: [String?] = [nil, "", "   "]
        for outputUID in invalidOutputUIDs {
            var writeCount = 0
            let state = BetterDisplayVolumeSettingsState(
                outputUID: outputUID,
                configuration: .default,
                devices: [],
                availability: .idle
            )
            BetterDisplayVolumeSettingsActions(
                state: state,
                setConfiguration: { _, _ in writeCount += 1 },
                refresh: {}
            ).setBackend(.betterDisplay)
            XCTAssertEqual(writeCount, 0)
        }
    }

    func testDisplaySelectionUsesUUIDAndPreservesUnassociatedBetterDisplayPreference() {
        var writtenConfigurations: [ExternalVolumeConfiguration] = []
        var writtenUIDs: [String] = []
        let recordWrite: (ExternalVolumeConfiguration, String) -> Void = {
            writtenConfigurations.append($0)
            writtenUIDs.append($1)
        }
        let state = BetterDisplayVolumeSettingsState(
            outputUID: "audio-display",
            configuration: ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: nil
            ),
            devices: [
                BetterDisplayDevice(uuid: "display-a", name: "Same Label"),
                BetterDisplayDevice(uuid: "display-b", name: "Same Label")
            ],
            availability: .available
        )
        let actions = BetterDisplayVolumeSettingsActions(
            state: state,
            setConfiguration: recordWrite,
            refresh: {}
        )

        actions.selectDisplayUUID("  display-b  ")
        XCTAssertEqual(writtenUIDs, ["audio-display"])
        XCTAssertEqual(
            writtenConfigurations,
            [
                ExternalVolumeConfiguration(
                    backend: .betterDisplay,
                    betterDisplayUUID: "display-b"
                )
            ]
        )

        writtenConfigurations.removeAll()
        writtenUIDs.removeAll()
        actions.selectDisplayUUID(nil)
        XCTAssertEqual(writtenUIDs, ["audio-display"])
        XCTAssertEqual(
            writtenConfigurations,
            [
                ExternalVolumeConfiguration(
                    backend: .betterDisplay,
                    betterDisplayUUID: nil
                )
            ]
        )

        var directWriteCount = 0
        let direct = BetterDisplayVolumeSettingsState(
            outputUID: "audio-display",
            configuration: .default,
            devices: [BetterDisplayDevice(uuid: "display-a", name: nil)],
            availability: .available
        )
        BetterDisplayVolumeSettingsActions(
            state: direct,
            setConfiguration: { _, _ in directWriteCount += 1 },
            refresh: {}
        ).selectDisplayUUID("display-a")
        XCTAssertEqual(directWriteCount, 0)
    }

    func testPickerRetainsConfiguredUUIDAndNeverChoosesFirstDevice() {
        let devices = [
            BetterDisplayDevice(uuid: "display-a", name: "Same Label"),
            BetterDisplayDevice(uuid: "display-b", name: "Same Label")
        ]
        let unassociated = BetterDisplayVolumeSettingsState(
            outputUID: "audio-display",
            configuration: ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: nil
            ),
            devices: devices,
            availability: .deviceUnassociated
        )

        XCTAssertNil(unassociated.selectedDisplayUUID)
        XCTAssertEqual(
            unassociated.pickerOptions.map(\.uuid),
            [nil, "display-a", "display-b"]
        )

        let stale = BetterDisplayVolumeSettingsState(
            outputUID: "audio-display",
            configuration: ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: "display-stale"
            ),
            devices: devices,
            availability: .deviceUnassociated
        )

        XCTAssertEqual(stale.selectedDisplayUUID, "display-stale")
        XCTAssertEqual(
            stale.pickerOptions,
            [
                .unassociated,
                .device(uuid: "display-a", name: "Same Label"),
                .device(uuid: "display-b", name: "Same Label"),
                .unavailable(uuid: "display-stale")
            ]
        )
    }

    func testRefreshDiscoveryDoesNotRequireAnExistingAssociation() {
        var refreshCount = 0
        let state = BetterDisplayVolumeSettingsState(
            outputUID: nil,
            configuration: .default,
            devices: [],
            availability: .idle
        )

        BetterDisplayVolumeSettingsActions(
            state: state,
            setConfiguration: { _, _ in },
            refresh: { refreshCount += 1 }
        ).refreshDevices()

        XCTAssertEqual(refreshCount, 1)
    }

    func testAudioSettingsAppearanceDoesNotStartAutomaticBetterDisplayDiscovery() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/StatusTrioCore/UI/Settings/AudioSectionView.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let onAppearStart = try XCTUnwrap(source.range(of: ".onAppear {"))
        let onAppearEnd = try XCTUnwrap(
            source[onAppearStart.upperBound...].range(of: "        }")
        )
        let onAppearBody = source[
            onAppearStart.upperBound..<onAppearEnd.lowerBound
        ]

        XCTAssertTrue(onAppearBody.contains("statusStore.refreshAll()"))
        XCTAssertFalse(onAppearBody.contains("refreshBetterDisplayDevices"))
    }

    func testAudioConnectionRequirementsAreShownDirectlyWithoutDisclosure() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/StatusTrioCore/UI/Settings/AudioSectionView.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("SettingsHintRow("))
        XCTAssertTrue(
            source.contains(".settingsAudioExternalVolumeRequirements")
        )
        XCTAssertFalse(
            source.contains("SettingsDisclosureRow("),
            "A one-line requirement should be directly visible instead of collapsed."
        )
        XCTAssertFalse(
            source.contains("connectionHelpExpanded"),
            "There is no disclosure state to manage for a directly visible hint."
        )
    }

    func testExternalVolumeTrailingControlsShareOneRightAlignedColumn() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/StatusTrioCore/UI/Settings/AudioSectionView.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let alignedControls = source.components(
            separatedBy: "ExternalVolumeTrailingControl {"
        ).count - 1

        XCTAssertEqual(
            alignedControls,
            4,
            "Output, both pickers, and Detect Again must share one right-aligned column."
        )

        let wrapperStart = try XCTUnwrap(
            source.range(of: "private struct ExternalVolumeTrailingControl")
        )
        let wrapperSource = String(source[wrapperStart.lowerBound...])
        XCTAssertTrue(
            wrapperSource.contains("Spacer(minLength: 0)"),
            "Trailing content must be pushed to the common column edge."
        )
        XCTAssertTrue(
            wrapperSource.contains(".layoutPriority(1)"),
            "Row compression must not shrink the shared trailing column."
        )
    }

    func testBetterDisplayAvailabilityMapsToLocalizedStatusCopy() {
        let expected: [(BetterDisplayAvailability, LocalizationKey)] = [
            (.idle, .settingsAudioExternalVolumeStatusIdle),
            (.discovering, .settingsAudioExternalVolumeStatusBusy),
            (.available, .settingsAudioExternalVolumeStatusReady),
            (.syncing, .settingsAudioExternalVolumeStatusUpdating),
            (.appAbsent, .settingsAudioExternalVolumeStatusAppAbsent),
            (.unresponsive, .settingsAudioExternalVolumeStatusUnresponsive),
            (.deviceUnassociated, .settingsAudioExternalVolumeStatusChooseDisplay),
            (.invalidResponse, .settingsAudioExternalVolumeStatusInvalidResponse),
            (.requestFailed, .settingsAudioExternalVolumeStatusRequestFailed),
            (.writeNotConfirmed, .settingsAudioExternalVolumeStatusNotConfirmed)
        ]

        for (availability, key) in expected {
            XCTAssertEqual(availability.settingsStatusLocalizationKey, key)
        }
    }

    func testBetterDisplaySettingsCopyLoadsInEveryShippedLocale() throws {
        XCTAssertEqual(AppLanguage.allCases.count, 12)
        let distinctFailureKeys: [LocalizationKey] = [
            .settingsAudioExternalVolumeStatusAppAbsent,
            .settingsAudioExternalVolumeStatusUnresponsive,
            .settingsAudioExternalVolumeStatusInvalidResponse,
            .settingsAudioExternalVolumeStatusRequestFailed
        ]

        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))
            for key in betterDisplayLocalizationKeys {
                let value = bundle.localizedString(
                    forKey: key.rawValue,
                    value: nil,
                    table: nil
                )
                XCTAssertFalse(
                    value.isEmpty,
                    "\(language.rawValue).lproj missing \(key.rawValue)"
                )
                XCTAssertNotEqual(
                    value,
                    key.rawValue,
                    "\(language.rawValue).lproj leaves \(key.rawValue) unresolved"
                )
            }

            let failureCopy = distinctFailureKeys.map { key in
                bundle.localizedString(
                    forKey: key.rawValue,
                    value: nil,
                    table: nil
                )
            }
            XCTAssertEqual(
                Set(failureCopy).count,
                distinctFailureKeys.count,
                "\(language.rawValue).lproj collapses distinct BetterDisplay failures"
            )
        }
    }

    private func makeLocalization(_ language: AppLanguage) -> Localization {
        let suiteName = "BetterDisplayVolumeUITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            TestUserDefaults.removeSuite(named: suiteName)
        }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        return localization
    }
}
