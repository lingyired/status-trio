import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
@Suite struct BLECancellationTimeoutRegistryTests {
    @Test func aLostDisconnectCallbackRunsTheTeardownAfterTheTimeout() async throws {
        let id = UUID()
        let sessionID = UUID()
        var fired: [UUID] = []
        let registry = BLECancellationTimeoutRegistry(
            timeout: .milliseconds(20),
            sleep: { _ in }
        )

        registry.begin(id: id, sessionID: sessionID) {
            fired.append(sessionID)
        }
        #expect(registry.pendingCount == 1)

        let elapsed = await waitUntil { fired == [sessionID] }
        #expect(elapsed)
        #expect(registry.pendingCount == 0)
    }

    @Test func aNormalDisconnectCancelsTheTimeout() async throws {
        let id = UUID()
        var fired = false
        let gate = AsyncTestGate()
        let registry = BLECancellationTimeoutRegistry(
            timeout: .milliseconds(20),
            sleep: { _ in try await gate.wait() }
        )

        registry.begin(id: id, sessionID: UUID()) { fired = true }
        registry.finish(id: id)
        #expect(registry.pendingCount == 0)

        gate.open()
        try await Task.sleep(for: .milliseconds(60))
        #expect(!fired)
    }

    @Test func replacingAnEntryForTheSamePeripheralReplacesItsSession() async throws {
        let id = UUID()
        let firstSession = UUID()
        let secondSession = UUID()
        var fired: [UUID] = []
        let registry = BLECancellationTimeoutRegistry(sleep: { _ in })

        registry.begin(id: id, sessionID: firstSession) { fired.append(firstSession) }
        registry.begin(id: id, sessionID: secondSession) { fired.append(secondSession) }
        registry.expireNow(id: id)

        #expect(fired == [secondSession])
        #expect(registry.pendingCount == 0)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        attempts: Int = 200
    ) async -> Bool {
        for _ in 0..<attempts {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }
}

@MainActor
private final class AsyncTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async throws {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
