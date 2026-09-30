import Testing
@testable import StatusTrioCore

@MainActor
struct BluetoothAudioIconOverrideSynchronizerTests {
    @Test("A refreshed selected AirPods 5 replaces a stale persisted symbol")
    func replacesStaleSymbolFromSelectedDevice() {
        let airPods = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:FF",
            name: "My Earbuds",
            kind: .audio,
            isConnected: true,
            airPodsModel: .airPodsGen5,
            vendorID: 0x004C,
            productID: 0x2030
        )
        let symbol = BluetoothDeviceRowIcon.symbolName(for: airPods)

        #expect(BluetoothAudioIconOverrideSynchronizer.update(
            currentSymbol: "headphones",
            selectedAddress: "aa-bb-cc-dd-ee-ff",
            devices: [airPods],
            availability: .available
        ) == .set(symbol))
        #expect(BluetoothAudioIconOverrideSynchronizer.update(
            currentSymbol: symbol,
            selectedAddress: "aa-bb-cc-dd-ee-ff",
            devices: [airPods],
            availability: .available
        ) == .unchanged)
    }

    @Test("An unavailable or missing selected device keeps the persisted symbol")
    func transientAbsenceKeepsCurrentSymbol() {
        let device = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:FF",
            name: "My Earbuds",
            kind: .audio,
            isConnected: true,
            airPodsModel: .airPodsGen5,
            vendorID: 0x004C,
            productID: 0x2030
        )

        #expect(BluetoothAudioIconOverrideSynchronizer.update(
            currentSymbol: "headphones",
            selectedAddress: "AABBCCDDEEFF",
            devices: [device],
            availability: .failed
        ) == .unchanged)
        #expect(BluetoothAudioIconOverrideSynchronizer.update(
            currentSymbol: "headphones",
            selectedAddress: "AABBCCDDEEFF",
            devices: [],
            availability: .available
        ) == .unchanged)
    }

    @Test("Selecting audio-device mode clears a stale device override")
    func audioDeviceModeClearsOverride() {
        #expect(BluetoothAudioIconOverrideSynchronizer.update(
            currentSymbol: "headphones",
            selectedAddress: nil,
            devices: [],
            availability: .idle
        ) == .clear)
        #expect(BluetoothAudioIconOverrideSynchronizer.update(
            currentSymbol: nil,
            selectedAddress: nil,
            devices: [],
            availability: .idle
        ) == .unchanged)
    }
}
