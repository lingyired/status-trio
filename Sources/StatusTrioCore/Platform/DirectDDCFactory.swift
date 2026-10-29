import Foundation

// Direct-only compatibility surface. Store source membership excludes this file
// together with the concrete transport, coordinator, and resolver.
@MainActor
extension VolumeMonitor {
    convenience init(
        statusReader: any AudioStatusReadingProviding = CoreAudioStatusReader(),
        appleBluetoothAudioDiagnosticReporter: AppleBluetoothAudioDiagnosticReporter = AppleBluetoothAudioDiagnosticReporter(),
        eventMonitor: any VolumeEventMonitoring = CoreAudioVolumeEventMonitor(),
        outputController: (any AudioOutputControlling)? = nil,
        ddcTransport: any DDCVolumeTransport = DDCDisplayTransport(),
        ddcCoordinator: DDCVolumeCoordinator? = nil,
        refreshDebounceInterval: Duration = .milliseconds(150),
        refreshDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        readTimeout: Duration = .seconds(5),
        readTimeoutSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        let coordinatorFactory: DDCVolumeCoordinatorFactory
        if let ddcCoordinator {
            coordinatorFactory = { _, _ in ddcCoordinator }
        } else {
            coordinatorFactory = { onUpdate, configuration in
                DDCVolumeCoordinator(
                    transport: ddcTransport,
                    debounce: configuration.debounce,
                    readWatchdog: configuration.readWatchdog,
                    beforeReadValidation: configuration.beforeReadValidation,
                    onReadCompletion: configuration.onReadCompletion,
                    onDebounceSettled: configuration.onDebounceSettled,
                    sleep: configuration.sleep,
                    onUpdate: onUpdate
                )
            }
        }

        self.init(
            statusReader: statusReader,
            appleBluetoothAudioDiagnosticReporter: appleBluetoothAudioDiagnosticReporter,
            eventMonitor: eventMonitor,
            outputController: outputController,
            ddcCoordinatorFactory: coordinatorFactory,
            refreshDebounceInterval: refreshDebounceInterval,
            refreshDebounceSleep: refreshDebounceSleep,
            readTimeout: readTimeout,
            readTimeoutSleep: readTimeoutSleep
        )
    }
}
