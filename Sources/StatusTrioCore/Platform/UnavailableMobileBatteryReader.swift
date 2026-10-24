import Foundation

struct UnavailableMobileBatteryReader: MobileBatteryReading {
    func discover() async throws -> [AppleDeviceCandidate] { [] }
    func read(selectedIDs: Set<AppleDeviceID>) async throws -> MobileBatteryReadResult {
        MobileBatteryReadResult()
    }
}
