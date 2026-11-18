import Foundation

struct IconDesignerEditSnapshot: Equatable {
    var configuration: IconConfigurationV1
    var airPodsAddress: String?
    var connectedBluetoothAddress: String?
    var bluetoothNetworkAddress: String?
    var refreshesAirPodsBatteryForIcon: Bool
    var bluetoothAudioIconChoice: BluetoothAudioIconChoice
}
