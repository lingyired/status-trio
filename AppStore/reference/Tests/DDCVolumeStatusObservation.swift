import XCTest
@testable import StatusTrioCore

/// Subscribes before a monitor starts and records statuses by intent instead of
/// by stream position. The monitor intentionally keeps only the newest pending
/// status, so positional reads can race and lose an intermediate update.
@MainActor
final class DDCVolumeStatusObservation {
    let attached = XCTestExpectation(description: "DDC volume observer is attached")

    private struct PendingExpectation {
        let expectation: XCTestExpectation
        let predicate: @MainActor (VolumeStatus) -> Bool
    }

    private var pendingExpectations: [PendingExpectation] = []
    private var fulfilledStatuses: [ObjectIdentifier: VolumeStatus] = [:]
    private var task: Task<Void, Never>?
    private(set) var latestStatus: VolumeStatus?

    func start(consuming updates: AsyncStream<VolumeStatus>) {
        precondition(task == nil, "The observation can only be started once")
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            // The test resumes only after this task suspends in the stream read,
            // which installs the subscription before the monitor can publish.
            attached.fulfill()
            for await status in updates {
                receive(status)
            }
        }
    }

    @discardableResult
    func expect(
        _ description: String,
        matching predicate: @escaping @MainActor (VolumeStatus) -> Bool
    ) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: description)
        pendingExpectations.append(PendingExpectation(
            expectation: expectation,
            predicate: predicate
        ))
        return expectation
    }

    func status(for expectation: XCTestExpectation) -> VolumeStatus? {
        fulfilledStatuses[ObjectIdentifier(expectation)]
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func receive(_ status: VolumeStatus) {
        latestStatus = status
        guard let index = pendingExpectations.firstIndex(where: {
            $0.predicate(status)
        }) else { return }
        let pending = pendingExpectations.remove(at: index)
        fulfilledStatuses[ObjectIdentifier(pending.expectation)] = status
        pending.expectation.fulfill()
    }
}
