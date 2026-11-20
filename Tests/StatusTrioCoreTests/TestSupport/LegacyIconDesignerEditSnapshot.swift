import Foundation
@testable import StatusTrioCore

/// Test-only snapshot for the retired 2.0 designer compatibility tests.
struct IconDesignerEditSnapshot: Equatable {
    var configuration: IconConfigurationV1
    var airPodsAddress: String?
    var connectedBluetoothAddress: String?
    var bluetoothNetworkAddress: String?
    var refreshesAirPodsBatteryForIcon: Bool
    var bluetoothAudioIconChoice: BluetoothAudioIconChoice
}
