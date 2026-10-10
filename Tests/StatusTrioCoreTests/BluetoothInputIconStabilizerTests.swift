import Foundation
import Testing
@testable import StatusTrioCore

/// The generic-input glyph must not flicker: a composite device classified
/// while both its interfaces are enumerated keeps the generic glyph even on a
/// read that happens to see only one of them.
@MainActor
struct BluetoothInputIconStabilizerTests {
    private func device(
        address: String = "E3:3D:B6:E4:74:73",
        name: String = "HECATE G3M Pro",
        classification: BluetoothInputIconClassification?
    ) -> BluetoothDevice {
        BluetoothDevice(
            id: address,
            name: name,
            kind: .peripheral(.mouse),
            isConnected: true,
            inputIconClassification: classification
        )
    }

    @Test func aGenericClassificationBecomesSticky() {
        var stabilizer = BluetoothInputIconStabilizer()

        let first = stabilizer.stabilize([device(classification: .genericInput)])
        #expect(first.first?.inputIconClassification == .genericInput)

        // A later read that saw only the mouse interface still draws generic.
        let second = stabilizer.stabilize([device(classification: .mouse)])
        #expect(second.first?.inputIconClassification == .genericInput)
    }

    @Test func aDefiniteClassificationIsLeftAloneUntilItTurnsGeneric() {
        var stabilizer = BluetoothInputIconStabilizer()

        let first = stabilizer.stabilize([device(classification: .mouse)])
        #expect(first.first?.inputIconClassification == .mouse)

        let second = stabilizer.stabilize([device(classification: nil)])
        #expect(second.first?.inputIconClassification == nil)
    }

    @Test func stickyStateSurvivesAReadWithNoObservation() {
        var stabilizer = BluetoothInputIconStabilizer()
        _ = stabilizer.stabilize([device(classification: .genericInput)])

        let next = stabilizer.stabilize([device(classification: nil)])
        #expect(next.first?.inputIconClassification == .genericInput)
    }

    /// Removing the device drops its entry, so a different device that later
    /// reuses the address does not inherit the sticky generic classification.
    @Test func anAbsentDeviceDropsItsStickyEntry() {
        var stabilizer = BluetoothInputIconStabilizer()
        _ = stabilizer.stabilize([device(address: "AA:BB:CC:DD:EE:FF", classification: .genericInput)])

        // The device is gone from this read.
        let empty = stabilizer.stabilize([])
        #expect(empty.isEmpty)

        // A new device at the same address starts from its own evidence.
        let reused = stabilizer.stabilize([
            device(address: "AA:BB:CC:DD:EE:FF", name: "Other", classification: .keyboard)
        ])
        #expect(reused.first?.inputIconClassification == .keyboard)
    }

    /// The Registry and the report spell the same address differently; the
    /// sticky set is keyed by the one normalization the app joins devices by.
    @Test func theStickyKeyJoinsBothAddressSpellings() {
        var stabilizer = BluetoothInputIconStabilizer()
        _ = stabilizer.stabilize([device(address: "e3-3d-b6-e4-74-73", classification: .genericInput)])

        let next = stabilizer.stabilize([device(address: "E3:3D:B6:E4:74:73", classification: .mouse)])
        #expect(next.first?.inputIconClassification == .genericInput)
    }

    /// An identifier that reduces to no address names no device, so it must
    /// never enter the sticky set. `ghijkl` has no hex digit at all, which is
    /// what an unnormalizable identifier looks like.
    @Test func anUnnormalizableAddressIsNeverCached() {
        var stabilizer = BluetoothInputIconStabilizer()
        #expect(BluetoothBatteryReader.normalizedAddress("ghijkl").isEmpty)

        let noAddress = BluetoothDevice(
            id: "ghijkl",
            name: "External",
            kind: .peripheral(.mouse),
            isConnected: true,
            inputIconClassification: .genericInput
        )

        _ = stabilizer.stabilize([noAddress])
        let next = stabilizer.stabilize([
            BluetoothDevice(
                id: "ghijkl",
                name: "External",
                kind: .peripheral(.mouse),
                isConnected: true,
                inputIconClassification: .keyboard
            )
        ])
        #expect(next.first?.inputIconClassification == .keyboard)
    }
}
