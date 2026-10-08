import Foundation
@testable import StatusTrioCore

enum PresentationFixtures {
    static func snapshot(
        rssi: Int = -61,
        scalar: Double? = 0.51,
        muted: Bool = false
    ) -> StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 68,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            wifi: WiFiStatus(state: .connected, rssi: rssi),
            connection: .wifi,
            volume: VolumeStatus(scalar: scalar, isMuted: muted, deviceName: "Output")
        )
    }

    static var bluetoothDevice: AudioOutputDevice { SheetFixtures.bluetoothDevice }
}
