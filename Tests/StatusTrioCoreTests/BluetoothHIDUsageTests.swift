import Foundation
import Testing
@testable import StatusTrioCore

/// The usage precedence that decides what a connected HID device really is.
///
/// The regression this pins: the Logitech `MX Keys` on the machine this was
/// written on reports `Mouse` in `device_minorType` while the system enumerates
/// `UsagePage 1 / Usage 6` for it — Generic Desktop keyboard, the interface
/// macOS loads a keyboard driver for. Trusting the report alone draws a mouse
/// glyph on the keyboard the user is typing on.
struct BluetoothHIDUsageClassifierTests {
    private func usage(_ page: Int, _ usage: Int) -> BluetoothHIDUsage {
        BluetoothHIDUsage(usagePage: page, usage: usage)
    }

    @Test func capabilitiesCollectEveryRecognizedInputRole() {
        let capabilities = BluetoothHIDCapabilities(usages: [
            usage(1, 2),       // mouse
            usage(1, 6),       // keyboard
            usage(0x0D, 0x05), // touch pad
            usage(1, 5),       // game pad
        ])

        #expect(capabilities.hasMouse)
        #expect(capabilities.hasKeyboard)
        #expect(capabilities.hasTrackpad)
        #expect(capabilities.hasGamepad)
    }

    @Test func unknownUsagesProduceNoCapabilities() {
        let capabilities = BluetoothHIDCapabilities(usages: [usage(0x0C, 1), usage(1, 0x80)])

        #expect(!capabilities.hasMouse)
        #expect(!capabilities.hasKeyboard)
        #expect(!capabilities.hasTrackpad)
        #expect(!capabilities.hasGamepad)
    }

    @Test func theKeyboardUsageIsAKeyboard() {
        #expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 6)], declared: nil) == .keyboard)
    }

    @Test func theKeypadUsageIsAKeyboard() {
        #expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 7)], declared: nil) == .keyboard)
    }

    @Test func theMouseUsageIsAMouse() {
        #expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 2)], declared: nil) == .mouse)
    }

    @Test func thePointerAndMultiAxisUsagesAreAMouse() {
        #expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 1)], declared: nil) == .mouse)
        #expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 8)], declared: nil) == .mouse)
    }

    @Test func theGamePadAndJoystickUsagesAreAGamepad() {
        #expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 5)], declared: nil) == .gamepad)
        #expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 4)], declared: nil) == .gamepad)
    }

    /// A trackpad enumerates as a pointer too, so the Digitizer page is what
    /// tells it apart from a mouse. Reading the pointer interface first would
    /// draw every trackpad as a mouse.
    @Test func theTouchPadUsageOutranksThePointerUsageItAlsoPresents() {
        #expect(
            BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 2), usage(0x0D, 0x05)], declared: nil)
                == .trackpad
        )
        #expect(
            BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 2), usage(0x0D, 0x22)], declared: nil)
                == .trackpad
        )
    }

    @Test func aDeclaredMouseOutranksAnAuxiliaryKeyboardInterface() {
        #expect(
            BluetoothHIDUsageClassifier.peripheralForm(
                from: [usage(1, 2), usage(1, 6)], declared: .mouse
            ) == .mouse
        )
    }

    @Test func aKeyboardOnlyUsageCorrectsAWronglyDeclaredMouse() {
        #expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 6)], declared: .mouse) == .keyboard)
    }

    @Test func aDeclaredKeyboardOutranksItsPointerInterface() {
        #expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 6), usage(1, 2)], declared: .keyboard) == .keyboard)
    }

    @Test func ambiguousMouseAndKeyboardWithoutADeclarationAnswerNothing() {
        #expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 2), usage(1, 6)], declared: nil) == nil)
    }

    @Test func aTrackpadOutranksAKeyboardOnTheSameDevice() {
        #expect(
            BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 6), usage(0x0D, 0x05)], declared: nil)
                == .trackpad
        )
    }

    /// Nothing here describes the device, so the declared class stands.
    @Test func usagesThatDescribeNoInputDeviceAnswerNothing() {
        #expect(BluetoothHIDUsageClassifier.peripheralForm(from: [], declared: nil) == nil)
        #expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(0x0C, 0x01)], declared: nil) == nil)
        #expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 0x80)], declared: nil) == nil)
    }
}

/// What the correction is allowed to change, and what it must leave alone.
struct BluetoothDeviceKindRefinementTests {
    private let keyboardUsage = BluetoothHIDUsage(usagePage: 1, usage: 6)
    private let mouseUsage = BluetoothHIDUsage(usagePage: 1, usage: 2)

    private func device(
        address: String = "D3:6D:6C:40:A3:2E",
        name: String = "MX Keys",
        kind: BluetoothDeviceKind,
        connected: Bool = true
    ) -> BluetoothDevice {
        BluetoothDevice(id: address, name: name, kind: kind, isConnected: connected)
    }

    /// The MX Keys regression, end to end: the report says mouse, the Registry
    /// says keyboard, and the keyboard wins.
    @Test func aWronglyDeclaredMouseIsCorrectedToAKeyboard() {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .peripheral(.mouse))],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        #expect(refined.first?.kind == .peripheral(.keyboard))
        #expect(refined.first?.name == "MX Keys")
    }

    @Test func aDeclaredMouseStaysMouseWhenItAlsoPresentsAKeyboardInterface() {
        for usages in [[mouseUsage, keyboardUsage], [keyboardUsage, mouseUsage]] {
            let refined = BluetoothDeviceKindRefinement.apply(
                to: [device(kind: .peripheral(.mouse))],
                hidUsages: ["D36D6C40A32E": usages]
            )

            #expect(refined.first?.kind == .peripheral(.mouse))
        }
    }

    /// Issue #88: a mouse whose macro keys make macOS order its keyboard
    /// collection first. The device presents a pointer usage too — the reader
    /// reads every usage pair, so the refinement sees it and the declared mouse
    /// survives instead of being read as a keyboard.
    @Test func aDeclaredMouseWithItsKeyboardCollectionFirstStaysMouse() {
        let usages = BluetoothHIDUsageReader.readUsages(from: 17) { _, key -> Any? in
            switch key as String {
            case "Transport": "Bluetooth Low Energy"
            case "DeviceAddress": "e3-3d-b6-e4-74-73"
            case "DeviceUsagePairs": [
                ["DeviceUsagePage": 1, "DeviceUsage": 6],   // keyboard/macro collection first
                ["DeviceUsagePage": 1, "DeviceUsage": 2],   // pointer usage the mouse needs
            ] as [[String: Any]]
            default: Optional<Any>.none
            }
        }
        let hidUsages = Dictionary(
            uniqueKeysWithValues: [usages].compactMap { value -> (String, [BluetoothHIDUsage])? in
                guard let value else { return nil }
                return (BluetoothBatteryReader.normalizedAddress(value.address), value.usages)
            }
        )

        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(address: "e3:3d:b6:e4:74:73", name: "HECATE G3M Pro", kind: .peripheral(.mouse))],
            hidUsages: hidUsages
        )

        #expect(refined.first?.kind == .peripheral(.mouse))
    }

    @Test func anUnknownKindStaysUnknownWhenMouseAndKeyboardAreAmbiguous() {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .unknown)],
            hidUsages: ["D36D6C40A32E": [mouseUsage, keyboardUsage]]
        )

        #expect(refined.first?.kind == .unknown)
    }

    @Test func aDeclaredKeyboardStaysKeyboardWithItsPointerInterface() {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .peripheral(.keyboard))],
            hidUsages: ["D36D6C40A32E": [mouseUsage, keyboardUsage]]
        )

        #expect(refined.first?.kind == .peripheral(.keyboard))
    }

    @Test func aDisconnectedDeviceIgnoresStaleHIDUsages() {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .peripheral(.mouse), connected: false)],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        #expect(refined.first?.kind == .peripheral(.mouse))
    }

    /// The Registry writes an address `d3-6d-6c-40-a3-2e` and the report
    /// writes the same device `D3:6D:6C:40:A3:2E`. The reader keys usages by the
    /// one normalization the app already keys battery levels by, and the join
    /// normalizes the device identifier the same way, so the two meet.
    @Test func theAddressIsJoinedAcrossBothSpellings() {
        #expect(BluetoothBatteryReader.normalizedAddress("d3-6d-6c-40-a3-2e") == "D36D6C40A32E")

        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(address: "d3:6d:6c:40:a3:2e", kind: .peripheral(.mouse))],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        #expect(refined.first?.kind == .peripheral(.keyboard))
    }

    /// IORegistry reports the interface the device presents, so a device the
    /// app could not classify at all is corrected into the family rather than
    /// left generic.
    @Test func anUnclassifiedDeviceIsCorrectedToo() {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .unknown)],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        #expect(refined.first?.kind == .peripheral(.keyboard))
    }

    /// An audio device, a phone or a computer is never reclassified: none of
    /// them declares a peripheral class, so a HID interface they happen to
    /// expose must not move them into that family.
    @Test(arguments: [
        BluetoothDeviceKind.audio,
        .computer(.laptop),
        .mobile(.phone),
        .mobile(.tablet),
        .imaging(.printer),
    ])
    func otherFamiliesAreNeverReclassified(kind: BluetoothDeviceKind) {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: kind)],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        #expect(refined.first?.kind == kind)
    }

    /// A paired but disconnected device has no Registry node, so its declared
    /// class stands — the same answer the app gave before this correction
    /// existed.
    @Test func aDeviceTheRegistryDoesNotKnowKeepsItsDeclaredClass() {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .peripheral(.mouse))],
            hidUsages: [:]
        )

        #expect(refined.first?.kind == .peripheral(.mouse))
    }

    /// A declared keyboard the Registry also calls a keyboard is left exactly
    /// as it was — the correction only ever moves a device to what the system
    /// enumerates, and here that is the same answer.
    @Test func agreementChangesNothing() {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .peripheral(.keyboard))],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        #expect(refined.first?.kind == .peripheral(.keyboard))
    }

    @Test func everyDeviceInTheListKeepsItsPlace() {
        let devices = [
            device(address: "AA:BB:CC:DD:EE:FF", name: "AirPods", kind: .audio),
            // Declared a mouse, and corrected to the keyboard it is.
            device(address: "D3:6D:6C:40:A3:2E", name: "MX Keys", kind: .peripheral(.mouse)),
            device(address: "E3:58:42:F3:6D:02", name: "M585/M590", kind: .peripheral(.mouse)),
        ]
        let refined = BluetoothDeviceKindRefinement.apply(
            to: devices,
            hidUsages: [
                "D36D6C40A32E": [keyboardUsage],
                "E35842F36D02": [mouseUsage],
            ]
        )

        #expect(refined.map(\.name) == ["AirPods", "MX Keys", "M585/M590"])
        #expect(refined.map(\.kind) == [.audio, .peripheral(.keyboard), .peripheral(.mouse)])
    }
}

/// The reader's own wiring: the correction runs, and the Registry is not walked
/// when the report carries nothing it could correct.
struct BluetoothPairedDeviceWorkerRefinementTests {
    private let keyboardUsage = BluetoothHIDUsage(usagePage: 1, usage: 6)

    private let mouseAndKeyboardReport = """
    {"SPBluetoothDataType": [{"device_connected": [
      {"MX Keys": {"device_address": "D3:6D:6C:40:A3:2E", "device_minorType": "Mouse"}}
    ]}]}
    """

    private let audioOnlyReport = """
    {"SPBluetoothDataType": [{"device_connected": [
      {"AirPods": {"device_address": "AC:90:85:C2:9C:1F", "device_minorType": "Headphones"}}
    ]}]}
    """

    @Test func theWorkerCorrectsADeclaredClassFromTheRegistry() async {
        let worker = SystemProfilerBluetoothPairedDeviceWorker(
            outputProvider: { Data(self.mouseAndKeyboardReport.utf8) },
            hidUsageProvider: { ["D36D6C40A32E": [self.keyboardUsage]] }
        )
        let box = WorkerResultBox()

        worker.read { box.set($0) }
        await waitForWorker(box)

        guard case .success(let devices) = box.value else {
            Issue.record("expected a successful read, got \(String(describing: box.value))")
            return
        }
        #expect(devices.first?.kind == .peripheral(.keyboard))
    }

    /// The same rule that keeps `pmset` from running when the report already
    /// carries every level: a second source is consulted only where the first
    /// left a question the app can answer.
    @Test func theRegistryIsNotWalkedWhenNothingNeedsCorrecting() async {
        let calls = CallCounter()
        let worker = SystemProfilerBluetoothPairedDeviceWorker(
            outputProvider: { Data(self.audioOnlyReport.utf8) },
            hidUsageProvider: {
                calls.increment()
                return [:]
            }
        )
        let box = WorkerResultBox()

        worker.read { box.set($0) }
        await waitForWorker(box)

        #expect(calls.value == 0)
        guard case .success(let devices) = box.value else {
            Issue.record("expected a successful read, got \(String(describing: box.value))")
            return
        }
        #expect(devices.first?.kind == .audio)
    }

    private func waitForWorker(_ box: WorkerResultBox) async {
        for _ in 0..<500 {
            if box.value != nil { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for the profiler read")
    }
}

private final class WorkerResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: BluetoothWorkerResult?

    var value: BluetoothWorkerResult? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ result: BluetoothWorkerResult) {
        lock.lock()
        stored = result
        lock.unlock()
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

/// The I/O Registry lookup stays limited to the values needed to join
/// Bluetooth HID interfaces to paired devices and classify their usage.
struct BluetoothHIDRegistryPropertyReadTests {
    @Test func bluetoothUsageReadsEveryTopLevelPair() {
        var lookedUp: [String] = []
        let result = BluetoothHIDUsageReader.readUsages(from: 17) { _, key -> Any? in
            lookedUp.append(key as String)
            return switch key as String {
            case "Transport": "Bluetooth Low Energy"
            case "DeviceAddress": "d3-6d-6c-40-a3-2e"
            case "DeviceUsagePairs": [
                ["DeviceUsagePage": 1, "DeviceUsage": 6],   // keyboard first
                ["DeviceUsagePage": 1, "DeviceUsage": 2],   // mouse too
            ] as [[String: Any]]
            default: Optional<Any>.none
            }
        }

        #expect(lookedUp == ["Transport", "DeviceAddress", "DeviceUsagePairs"])
        #expect(result?.address == "d3-6d-6c-40-a3-2e")
        #expect(result?.usages == [
            BluetoothHIDUsage(usagePage: 1, usage: 6),
            BluetoothHIDUsage(usagePage: 1, usage: 2),
        ])
    }

    /// Without usage pairs the primary usage is the device's one interface, and
    /// the fallback still reads it.
    @Test func thePrimaryUsageStandsInWhenNoPairsArePresent() {
        var lookedUp: [String] = []
        let result = BluetoothHIDUsageReader.readUsages(from: 17) { _, key -> Any? in
            lookedUp.append(key as String)
            return switch key as String {
            case "Transport": "Bluetooth Low Energy"
            case "DeviceAddress": "d3-6d-6c-40-a3-2e"
            case "PrimaryUsagePage": 1
            case "PrimaryUsage": 6
            default: Optional<Any>.none
            }
        }

        #expect(lookedUp == ["Transport", "DeviceAddress", "DeviceUsagePairs", "PrimaryUsagePage", "PrimaryUsage"])
        #expect(result?.usages == [BluetoothHIDUsage(usagePage: 1, usage: 6)])
    }

    @Test func nonBluetoothHIDServicesOnlyReadTransport() {
        var lookedUp: [String] = []
        let result = BluetoothHIDUsageReader.readUsages(from: 18) { _, key -> Any? in
            lookedUp.append(key as String)
            return "USB"
        }

        #expect(lookedUp == ["Transport"])
        #expect(result == nil)
    }
}
