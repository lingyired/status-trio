import Foundation
import Testing
@testable import StatusTrioCore

/// The display classification a connected HID device's row draws.
///
/// The regression this pins: a mouse that also presents a keyboard interface —
/// the MX Keys declares `Mouse` while the system enumerates keyboard, and a
/// macro mouse like the M585/M590 enumerates both — cannot be told apart by any
/// HID signal. Rather than guess a definite mouse or keyboard glyph, the row
/// draws the generic input glyph. The declared `kind` itself is never changed.
struct BluetoothInputIconClassifierTests {
    private func usage(_ page: Int, _ usage: Int) -> BluetoothHIDUsage {
        BluetoothHIDUsage(usagePage: page, usage: usage)
    }

    private func classify(_ declared: BluetoothDeviceKind, _ usages: [BluetoothHIDUsage])
        -> BluetoothInputIconClassification? {
        BluetoothInputIconClassifier.classify(
            declared: declared,
            capabilities: BluetoothHIDCapabilities(usages: usages)
        )
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

    // MARK: - Agreement

    @Test func aDeclaredMouseThatPresentsOnlyAMouseIsAMouse() {
        #expect(classify(.peripheral(.mouse), [usage(1, 2)]) == .mouse)
        #expect(classify(.peripheral(.mouse), [usage(1, 1)]) == .mouse)   // pointer
        #expect(classify(.peripheral(.mouse), [usage(1, 8)]) == .mouse)   // multi-axis
    }

    @Test func aDeclaredKeyboardThatPresentsOnlyAKeyboardIsAKeyboard() {
        #expect(classify(.peripheral(.keyboard), [usage(1, 6)]) == .keyboard)
        #expect(classify(.peripheral(.keyboard), [usage(1, 7)]) == .keyboard) // keypad
    }

    // MARK: - Mixed capabilities

    /// The heart of the change: mouse and keyboard both present is not a
    /// keyboard and not a mouse — it is an input device the app cannot name.
    @Test func mixedMouseAndKeyboardDrawsTheGenericInputGlyph() {
        for declared in [BluetoothDeviceKind.peripheral(.mouse), .peripheral(.keyboard), .unknown, .peripheral(.unclassified)] {
            for usages in [[usage(1, 2), usage(1, 6)], [usage(1, 6), usage(1, 2)]] {
                #expect(classify(declared, usages) == .genericInput, "\(declared) with \(usages)")
            }
        }
    }

    // MARK: - Conflict

    /// The declared class and the only interface the device presents disagree.
    /// Either could be the wrong one, so the row refuses to name the device.
    @Test func aDeclaredMouseThatPresentsOnlyAKeyboardIsGeneric() {
        #expect(classify(.peripheral(.mouse), [usage(1, 6)]) == .genericInput)
    }

    @Test func aDeclaredKeyboardThatPresentsOnlyAMouseIsGeneric() {
        #expect(classify(.peripheral(.keyboard), [usage(1, 2)]) == .genericInput)
    }

    // MARK: - Unknown and unclassified

    @Test func anUnclassifiedDeviceIsNamedByItsOnlyInterface() {
        #expect(classify(.unknown, [usage(1, 2)]) == .mouse)
        #expect(classify(.unknown, [usage(1, 6)]) == .keyboard)
        #expect(classify(.peripheral(.unclassified), [usage(1, 2)]) == .mouse)
        #expect(classify(.peripheral(.unclassified), [usage(1, 6)]) == .keyboard)
    }

    // MARK: - Specialized forms

    /// A touch pad enumerates as a pointer too, so the Digitizer page is what
    /// tells it apart from a mouse. Reading the pointer interface first would
    /// draw every trackpad as a mouse.
    @Test func theTouchPadUsageOutranksThePointerUsageItAlsoPresents() {
        #expect(classify(.unknown, [usage(1, 2), usage(0x0D, 0x05)]) == .trackpad)
        #expect(classify(.unknown, [usage(1, 2), usage(0x0D, 0x22)]) == .trackpad)
    }

    @Test func theGamePadAndJoystickUsagesAreAGamepad() {
        #expect(classify(.unknown, [usage(1, 5)]) == .gamepad)
        #expect(classify(.unknown, [usage(1, 4)]) == .gamepad)
    }

    /// A declared trackpad or gamepad only accepts a matching specialized
    /// usage. A pointing or keyboard interface it also exposes must not
    /// downgrade it to a mouse or keyboard glyph.
    @Test func aDeclaredTrackpadOrGamepadIsNotDowngradedByAnAuxiliaryInterface() {
        #expect(classify(.peripheral(.trackpad), [usage(1, 2)]) == nil)
        #expect(classify(.peripheral(.trackpad), [usage(1, 6)]) == nil)
        #expect(classify(.peripheral(.gamepad), [usage(1, 2)]) == nil)
        #expect(classify(.peripheral(.trackpad), [usage(0x0D, 0x05)]) == .trackpad)
        #expect(classify(.peripheral(.gamepad), [usage(1, 5)]) == .gamepad)
    }

    // MARK: - No evidence

    /// Nothing here describes the device, so the declared class stands.
    @Test func usagesThatDescribeNoInputDeviceAnswerNothing() {
        #expect(classify(.peripheral(.mouse), []) == nil)
        #expect(classify(.peripheral(.mouse), [usage(0x0C, 0x01)]) == nil)
        #expect(classify(.unknown, [usage(1, 0x80)]) == nil)
    }

    /// An audio device, a phone or a computer never draws an input glyph: a HID
    /// interface one of them happens to expose must not move it into the family.
    @Test(arguments: [
        BluetoothDeviceKind.audio,
        .computer(.laptop),
        .mobile(.phone),
        .mobile(.tablet),
        .imaging(.printer),
    ])
    func otherFamiliesNeverDrawAnInputGlyph(kind: BluetoothDeviceKind) {
        #expect(classify(kind, [usage(1, 2), usage(1, 6)]) == nil)
        #expect(classify(kind, [usage(1, 2)]) == nil)
    }
}

/// How the seed turns HID interfaces into a device's display classification,
/// and what it must leave alone. The declared `kind` is never changed.
struct BluetoothInputIconSeedTests {
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

    /// A declared mouse that presents only a keyboard interface is a conflict:
    /// the row draws the generic glyph, and the class stays as declared.
    @Test func aConflictingDeclaredMouseIsGenericButKeepsItsKind() {
        let seeded = BluetoothInputIconSeed.apply(
            to: [device(kind: .peripheral(.mouse))],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        #expect(seeded.first?.inputIconClassification == .genericInput)
        #expect(seeded.first?.kind == .peripheral(.mouse))
        #expect(seeded.first?.name == "MX Keys")
    }

    /// The composite mouse regression, end to end: a mouse that also presents a
    /// keyboard interface — macro keys, or a keyboard collection macOS orders
    /// first — is generic, not a definite mouse or keyboard.
    @Test func aCompositeMouseIsGenericInEitherInterfaceOrder() {
        for usages in [[mouseUsage, keyboardUsage], [keyboardUsage, mouseUsage]] {
            let seeded = BluetoothInputIconSeed.apply(
                to: [device(kind: .peripheral(.mouse))],
                hidUsages: ["D36D6C40A32E": usages]
            )

            #expect(seeded.first?.inputIconClassification == .genericInput)
            #expect(seeded.first?.kind == .peripheral(.mouse))
        }
    }

    /// Issue #88: a mouse whose macro keys make macOS order its keyboard
    /// collection first. The reader reads every usage pair, so the seed sees
    /// the pointer usage too and the row draws the generic input glyph.
    @Test func aDeclaredMouseWithItsKeyboardCollectionFirstIsGeneric() {
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

        let seeded = BluetoothInputIconSeed.apply(
            to: [device(address: "e3:3d:b6:e4:74:73", name: "HECATE G3M Pro", kind: .peripheral(.mouse))],
            hidUsages: hidUsages
        )

        #expect(seeded.first?.inputIconClassification == .genericInput)
        #expect(seeded.first?.kind == .peripheral(.mouse))
    }

    @Test func anUnknownKindWithMixedInterfacesIsGenericAndStaysUnknown() {
        let seeded = BluetoothInputIconSeed.apply(
            to: [device(kind: .unknown)],
            hidUsages: ["D36D6C40A32E": [mouseUsage, keyboardUsage]]
        )

        #expect(seeded.first?.inputIconClassification == .genericInput)
        #expect(seeded.first?.kind == .unknown)
    }

    @Test func aDeclaredKeyboardWithItsPointerInterfaceIsGeneric() {
        let seeded = BluetoothInputIconSeed.apply(
            to: [device(kind: .peripheral(.keyboard))],
            hidUsages: ["D36D6C40A32E": [mouseUsage, keyboardUsage]]
        )

        #expect(seeded.first?.inputIconClassification == .genericInput)
        #expect(seeded.first?.kind == .peripheral(.keyboard))
    }

    @Test func aDisconnectedDeviceIgnoresStaleHIDUsages() {
        let seeded = BluetoothInputIconSeed.apply(
            to: [device(kind: .peripheral(.mouse), connected: false)],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        #expect(seeded.first?.inputIconClassification == nil)
        #expect(seeded.first?.kind == .peripheral(.mouse))
    }

    /// The Registry writes an address `d3-6d-6c-40-a3-2e` and the report
    /// writes the same device `D3:6D:6C:40:A3:2E`. The reader keys usages by the
    /// one normalization the app already keys battery levels by, and the join
    /// normalizes the device identifier the same way, so the two meet.
    @Test func theAddressIsJoinedAcrossBothSpellings() {
        #expect(BluetoothBatteryReader.normalizedAddress("d3-6d-6c-40-a3-2e") == "D36D6C40A32E")

        let seeded = BluetoothInputIconSeed.apply(
            to: [device(address: "d3:6d:6c:40:a3:2e", kind: .peripheral(.mouse))],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        #expect(seeded.first?.inputIconClassification == .genericInput)
    }

    /// A device the app could not classify, that presents a single interface, is
    /// named by that interface — but its `kind` stays as declared.
    @Test func anUnclassifiedDeviceIsNamedByItsInterface() {
        let seeded = BluetoothInputIconSeed.apply(
            to: [device(kind: .unknown)],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        #expect(seeded.first?.inputIconClassification == .keyboard)
        #expect(seeded.first?.kind == .unknown)
    }

    /// An audio device, a phone or a computer never draws an input glyph.
    @Test(arguments: [
        BluetoothDeviceKind.audio,
        .computer(.laptop),
        .mobile(.phone),
        .mobile(.tablet),
        .imaging(.printer),
    ])
    func otherFamiliesAreNeverClassified(kind: BluetoothDeviceKind) {
        let seeded = BluetoothInputIconSeed.apply(
            to: [device(kind: kind)],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        #expect(seeded.first?.inputIconClassification == nil)
        #expect(seeded.first?.kind == kind)
    }

    /// A paired but disconnected device has no Registry node, so nothing is
    /// classified and the declared class stands.
    @Test func aDeviceTheRegistryDoesNotKnowKeepsItsDeclaredClass() {
        let seeded = BluetoothInputIconSeed.apply(
            to: [device(kind: .peripheral(.mouse))],
            hidUsages: [:]
        )

        #expect(seeded.first?.inputIconClassification == nil)
        #expect(seeded.first?.kind == .peripheral(.mouse))
    }

    /// A declared keyboard the Registry also calls a keyboard is named exactly:
    /// the interfaces agree with the declaration.
    @Test func agreementNamesTheDevice() {
        let seeded = BluetoothInputIconSeed.apply(
            to: [device(kind: .peripheral(.keyboard))],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        #expect(seeded.first?.inputIconClassification == .keyboard)
        #expect(seeded.first?.kind == .peripheral(.keyboard))
    }

    @Test func everyDeviceInTheListKeepsItsPlace() {
        let devices = [
            device(address: "AA:BB:CC:DD:EE:FF", name: "AirPods", kind: .audio),
            // Declared a mouse, and its only interface is a keyboard: generic.
            device(address: "D3:6D:6C:40:A3:2E", name: "MX Keys", kind: .peripheral(.mouse)),
            device(address: "E3:58:42:F3:6D:02", name: "M585/M590", kind: .peripheral(.mouse)),
        ]
        let seeded = BluetoothInputIconSeed.apply(
            to: devices,
            hidUsages: [
                "D36D6C40A32E": [keyboardUsage],
                "E35842F36D02": [mouseUsage],
            ]
        )

        #expect(seeded.map(\.name) == ["AirPods", "MX Keys", "M585/M590"])
        #expect(seeded.map(\.kind) == [.audio, .peripheral(.mouse), .peripheral(.mouse)])
        #expect(seeded.map(\.inputIconClassification) == [nil, .genericInput, .mouse])
    }
}

/// The reader's own wiring: the classification runs, and the Registry is not
/// walked when the report carries nothing it could classify.
struct BluetoothPairedDeviceWorkerClassificationTests {
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

    @Test func theWorkerClassifiesADeclaredMouseFromTheRegistry() async {
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
        // Declared mouse, keyboard-only interface: a conflict, drawn generic.
        #expect(devices.first?.inputIconClassification == .genericInput)
        #expect(devices.first?.kind == .peripheral(.mouse))
    }

    /// The same rule that keeps `pmset` from running when the report already
    /// carries every level: a second source is consulted only where the first
    /// left a question the app can answer.
    @Test func theRegistryIsNotWalkedWhenNothingNeedsClassifying() async {
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
        #expect(devices.first?.inputIconClassification == nil)
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
