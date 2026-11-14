import CoreAudio
import XCTest
@testable import StatusTrioCore

@MainActor
final class AudioPriorityTests: XCTestCase {
    private let builtIn = AudioPriorityDevice(id: 1, uid: "built-in", name: "Built-in")
    private let usb = AudioPriorityDevice(id: 2, uid: "usb", name: "USB")
    private let headphones = AudioPriorityDevice(id: 3, uid: "headphones", name: "Headphones")
    private var configuration: AudioPriorityConfiguration {
        AudioPriorityConfiguration(enabled: true, order: ["headphones", "usb", "built-in"])
    }

    func testSelectorSkipsHiddenDisconnectedAndUnstableIdentities() {
        let unstable = AudioPriorityDevice(id: 9, uid: nil, name: "USB")
        var config = configuration
        XCTAssertEqual(AudioPrioritySelector.target(devices: [builtIn, unstable, usb], configuration: config), usb)
        config.hiddenUIDs = ["usb"]
        XCTAssertEqual(AudioPrioritySelector.target(devices: [unstable, usb, builtIn], configuration: config), builtIn)
        config.hiddenUIDs.insert("built-in")
        XCTAssertNil(AudioPrioritySelector.target(devices: [unstable, usb, builtIn], configuration: config))
        config.enabled = false
        XCTAssertNil(AudioPrioritySelector.target(devices: [headphones], configuration: config))
    }

    func testConnectDisconnectSelectsHighestPriorityAndDoesNotLoopOnOwnReadback() {
        let coordinator = AudioPriorityCoordinator()
        var selected: [UInt32] = []
        coordinator.select = { id, _, done in selected.append(id); done(true) }
        coordinator.configure(configuration)
        coordinator.receive(devices: [builtIn], currentID: 1)
        XCTAssertTrue(selected.isEmpty)
        coordinator.receive(devices: [builtIn, usb], currentID: 1)
        XCTAssertEqual(selected, [2])
        coordinator.receive(devices: [builtIn, usb], currentID: 2)
        coordinator.receive(devices: [builtIn, usb], currentID: 2)
        XCTAssertEqual(selected, [2])
        coordinator.receive(devices: [builtIn, usb, headphones], currentID: 2)
        coordinator.receive(devices: [builtIn, usb, headphones], currentID: 3)
        coordinator.receive(devices: [builtIn, usb], currentID: 1)
        XCTAssertEqual(selected, [2, 3, 2])
    }

    func testManualChoiceLastsUntilSameDirectionTopologyChanges() {
        let coordinator = AudioPriorityCoordinator()
        var selected: [UInt32] = []
        coordinator.select = { id, _, done in selected.append(id); done(true) }
        coordinator.configure(configuration)
        coordinator.receive(devices: [builtIn, usb], currentID: 2)
        coordinator.manuallySelected()
        coordinator.receive(devices: [builtIn, usb], currentID: 1)
        coordinator.receive(devices: [builtIn, usb], currentID: 1)
        XCTAssertTrue(selected.isEmpty)
        coordinator.receive(devices: [builtIn, usb, headphones], currentID: 1)
        XCTAssertEqual(selected, [3])
    }

    func testLowerPriorityDeviceConnectingCannotTakeDefaultAfterInventoryNotification() {
        let coordinator = AudioPriorityCoordinator(respectsExternalDefaultChanges: false)
        var selected: [UInt32] = []
        coordinator.select = { id, _, done in selected.append(id); done(true) }
        coordinator.configure(configuration)
        coordinator.receive(devices: [headphones], currentID: 3)
        // HAL can publish the new inventory before macOS changes the default.
        coordinator.receive(devices: [headphones, usb], currentID: 3)
        coordinator.receive(devices: [headphones, usb], currentID: 2)
        XCTAssertEqual(selected, [3], "A later default notification must restore the higher-priority microphone")
        coordinator.receive(devices: [headphones, usb], currentID: 3)
        // A second delayed takeover is another event, not a manual choice.
        coordinator.receive(devices: [headphones, usb], currentID: 2)
        XCTAssertEqual(selected, [3, 3])
        coordinator.receive(devices: [headphones, usb], currentID: 3)
        coordinator.manuallySelected()
        coordinator.receive(devices: [headphones, usb], currentID: 2)
        XCTAssertEqual(selected, [3, 3], "An explicit Status Trio selection must keep the lower-priority microphone")
    }

    func testInputPrioritySelectsHigherDeviceWhenItConnectsLastAndFallsBackWhenRemoved() {
        let coordinator = AudioPriorityCoordinator(respectsExternalDefaultChanges: false)
        var selected: [UInt32] = []
        coordinator.select = { id, _, done in selected.append(id); done(true) }
        coordinator.configure(configuration)
        coordinator.receive(devices: [builtIn, usb], currentID: 2)
        coordinator.receive(devices: [builtIn, usb, headphones], currentID: 2)
        XCTAssertEqual(selected, [3])
        coordinator.receive(devices: [builtIn, usb, headphones], currentID: 3)
        coordinator.receive(devices: [builtIn, usb], currentID: 1)
        XCTAssertEqual(selected, [3, 2])
        coordinator.receive(devices: [builtIn, usb], currentID: 2)
        coordinator.receive(devices: [builtIn], currentID: nil)
        XCTAssertEqual(selected, [3, 2, 1])
    }

    func testDelayedSystemTakeoverDoesNotCancelPendingPriorityWrite() {
        let coordinator = AudioPriorityCoordinator(respectsExternalDefaultChanges: false)
        var request: AudioPriorityRequest?
        var completion: AudioPriorityCompletion?
        var selected: [UInt32] = []
        coordinator.select = { id, token, done in
            selected.append(id)
            request = token
            completion = done
        }
        coordinator.configure(configuration)
        coordinator.receive(devices: [builtIn, usb], currentID: 2)
        coordinator.receive(devices: [builtIn, usb, headphones], currentID: 2)
        coordinator.receive(devices: [builtIn, usb, headphones], currentID: 1)
        XCTAssertEqual(request?.isValid, true, "An unmarked system default change must not cancel the priority write")
        completion?(true)
        coordinator.receive(devices: [builtIn, usb, headphones], currentID: 3)
        XCTAssertEqual(selected, [3])
    }

    func testExternalManualChoiceAndNameChangesDoNotApplyPriorityAgain() {
        let coordinator = AudioPriorityCoordinator()
        var selected: [UInt32] = []
        coordinator.select = { id, _, done in selected.append(id); done(true) }
        coordinator.configure(configuration)
        coordinator.receive(devices: [builtIn, usb], currentID: 2)
        coordinator.receive(devices: [builtIn, usb], currentID: 1)
        let renamed = AudioPriorityDevice(id: 2, uid: "usb", name: "Renamed")
        coordinator.receive(devices: [builtIn, renamed], currentID: 1)
        XCTAssertTrue(selected.isEmpty)
        var changed = configuration
        changed.hiddenUIDs = ["built-in"]
        coordinator.configure(changed)
        coordinator.receive(devices: [builtIn, renamed], currentID: 1)
        XCTAssertEqual(selected, [2])
    }

    func testManualSelectionCancelsQueuedWriteAndIgnoresLateCompletion() {
        let coordinator = AudioPriorityCoordinator()
        var request: AudioPriorityRequest?
        var completion: AudioPriorityCompletion?
        var failures: [Bool] = []
        coordinator.onFailure = { failures.append($0) }
        coordinator.select = { _, token, done in request = token; completion = done }
        coordinator.configure(configuration)
        coordinator.receive(devices: [builtIn, usb], currentID: 1)
        XCTAssertEqual(request?.expectedUID, "usb")
        coordinator.manuallySelected()
        XCTAssertEqual(request?.isValid, false)
        completion?(false)
        coordinator.receive(devices: [builtIn, usb], currentID: 1)
        XCTAssertTrue(failures.isEmpty)
    }

    func testDisableAndStopInvalidatePendingRequest() {
        for stop in [false, true] {
            let coordinator = AudioPriorityCoordinator()
            var request: AudioPriorityRequest?
            coordinator.select = { _, token, _ in request = token }
            coordinator.configure(configuration)
            coordinator.receive(devices: [builtIn, usb], currentID: 1)
            if stop { coordinator.stop() } else { coordinator.configure(AudioPriorityConfiguration()) }
            XCTAssertEqual(request?.isValid, false)
        }
    }

    func testFailureDoesNotRetryUntilRulesOrTopologyChange() {
        let coordinator = AudioPriorityCoordinator(respectsExternalDefaultChanges: false)
        var attempts = 0
        var failed = false
        coordinator.select = { _, _, done in attempts += 1; done(false) }
        coordinator.onFailure = { failed = $0 }
        coordinator.configure(configuration)
        coordinator.receive(devices: [builtIn, usb], currentID: 1)
        XCTAssertTrue(failed)
        for _ in 0..<10 { coordinator.receive(devices: [builtIn, usb], currentID: 1) }
        coordinator.receive(devices: [builtIn, usb], currentID: nil)
        coordinator.receive(devices: [builtIn, usb], currentID: 1)
        XCTAssertEqual(attempts, 1)
        coordinator.receive(devices: [builtIn, usb, headphones], currentID: 1)
        XCTAssertEqual(attempts, 2)
    }

    func testReadbackMustConfirmSameUIDAndInputOutputRemainIndependent() {
        let input = AudioPriorityCoordinator()
        let output = AudioPriorityCoordinator()
        var inputAttempts = 0
        var outputAttempts = 0
        input.select = { _, _, done in inputAttempts += 1; done(true) }
        output.select = { _, _, done in outputAttempts += 1; done(true) }
        input.configure(configuration)
        output.configure(configuration)
        input.receive(devices: [builtIn, usb], currentID: 2)
        input.manuallySelected()
        output.receive(devices: [builtIn, usb], currentID: 1)
        output.receive(devices: [builtIn, usb], currentID: 2)
        input.receive(devices: [builtIn, usb], currentID: 1)
        XCTAssertEqual(inputAttempts, 0)
        XCTAssertEqual(outputAttempts, 1)
    }

    func testReconnectWithDifferentDeviceIDUsesStablePriority() {
        let coordinator = AudioPriorityCoordinator()
        var selected: [UInt32] = []
        coordinator.select = { id, _, done in selected.append(id); done(true) }
        coordinator.configure(configuration)
        coordinator.receive(devices: [builtIn, usb], currentID: 2)
        coordinator.receive(devices: [builtIn], currentID: 1)
        let reconnected = AudioPriorityDevice(id: 99, uid: "usb", name: "USB")
        coordinator.receive(devices: [builtIn, reconnected], currentID: 1)
        XCTAssertEqual(selected, [99])
    }

    func testSettingsDefaultOffMigrationMemoryAndForget() throws {
        let suite = "AudioPriorityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        defaults.set(["usb", "offline", "built-in"], forKey: SettingsStore.outputDeviceOrderDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.automaticallySwitchesInput)
        XCTAssertFalse(settings.automaticallySwitchesOutput)
        settings.rememberAudioDevices([builtIn, usb], currentID: 1, input: false)
        XCTAssertEqual(settings.outputDeviceOrder, ["usb", "offline", "built-in"])
        settings.setOutputDeviceHidden("usb", hidden: true)
        settings.automaticallySwitchesOutput = true
        let reopened = SettingsStore(defaults: defaults)
        XCTAssertTrue(reopened.automaticallySwitchesOutput)
        XCTAssertFalse(reopened.automaticallySwitchesInput)
        XCTAssertEqual(reopened.rememberedAudioOutputs.count, 2)
        reopened.forgetAudioDevice("usb", input: false)
        XCTAssertFalse(reopened.outputDeviceOrder.contains("usb"))
        XCTAssertFalse(reopened.hiddenOutputDeviceUIDs.contains("usb"))
        XCTAssertFalse(reopened.rememberedAudioOutputs.contains { $0.uid == "usb" })
    }

    func testInitialOrderUsesCurrentThenStableNamesAndRetainsOfflineDevices() throws {
        let suite = "AudioPriorityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.rememberAudioDevices([headphones, usb, builtIn], currentID: 2, input: true)
        XCTAssertEqual(settings.inputDeviceOrder, ["usb", "built-in", "headphones"])
        settings.rememberAudioDevices([builtIn], currentID: 1, input: true)
        XCTAssertEqual(settings.rememberedAudioInputs.count, 3)
        settings.moveRememberedAudioDevices(fromOffsets: IndexSet(integer: 2), toOffset: 0,
                                           in: [RememberedAudioDevice(uid: "usb", name: "USB"),
                                                RememberedAudioDevice(uid: "built-in", name: "Built-in"),
                                                RememberedAudioDevice(uid: "headphones", name: "Headphones")], input: true)
        XCTAssertEqual(settings.inputDeviceOrder, ["headphones", "usb", "built-in"])
    }
}
