import Foundation

@MainActor
enum StoreDDCFactory {
    static func makeCoordinator(
        onUpdate: @escaping @MainActor (DDCVolumeUpdate) -> Void,
        configuration _: DDCVolumeCoordinatorConfiguration
    ) -> any DDCVolumeCoordinating {
        UnavailableDDCVolumeCoordinator()
    }
}
