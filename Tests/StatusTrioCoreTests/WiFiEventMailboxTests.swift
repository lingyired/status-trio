import Foundation
import XCTest
@testable import StatusTrioCore

final class WiFiEventMailboxTests: XCTestCase {
    func testBurstSchedulesOnlyOneDeliveryAndKeepsLatestRSSI() throws {
        let mailbox = WiFiEventMailbox()
        mailbox.activate(generation: 1)
        var deliveryCount = 0

        for index in 0..<10_000 {
            if mailbox.enqueue(
                .linkQuality(rssi: -40 - index % 40),
                generation: 1
            ) {
                deliveryCount += 1
            }
        }

        XCTAssertEqual(deliveryCount, 1)
        let batch = try XCTUnwrap(mailbox.take())
        XCTAssertTrue(batch.needsRefresh)
        XCTAssertEqual(batch.latestRSSI, -79)
        XCTAssertNil(mailbox.take())
        XCTAssertEqual(
            mailbox.diagnosticsSnapshot().maximumPendingSignals,
            10_000
        )
    }

    func testBatchKeepsInvalidationAndOtherSignals() throws {
        let mailbox = WiFiEventMailbox()
        mailbox.activate(generation: 1)

        XCTAssertTrue(mailbox.enqueue(.connectionInvalidated, generation: 1))
        XCTAssertFalse(mailbox.enqueue(.connectionInterrupted, generation: 1))
        XCTAssertFalse(mailbox.enqueue(.bssidChanged, generation: 1))

        let batch = try XCTUnwrap(mailbox.take())
        XCTAssertTrue(batch.connectionInvalidated)
        XCTAssertTrue(batch.connectionInterrupted)
        XCTAssertTrue(batch.associationChanged)
        XCTAssertTrue(batch.needsRefresh)
    }

    func testAssociationChangeDropsRSSIFromBeforeTheChange() throws {
        let mailbox = WiFiEventMailbox()
        mailbox.activate(generation: 1)

        XCTAssertTrue(mailbox.enqueue(.linkQuality(rssi: -50), generation: 1))
        XCTAssertFalse(mailbox.enqueue(.bssidChanged, generation: 1))

        let batch = try XCTUnwrap(mailbox.take())
        XCTAssertTrue(batch.associationChanged)
        XCTAssertNil(batch.latestRSSI)
    }

    func testRSSIAfterAssociationChangeSurvivesTheBatch() throws {
        let mailbox = WiFiEventMailbox()
        mailbox.activate(generation: 1)

        XCTAssertTrue(mailbox.enqueue(.bssidChanged, generation: 1))
        XCTAssertFalse(mailbox.enqueue(.linkQuality(rssi: -61), generation: 1))

        let batch = try XCTUnwrap(mailbox.take())
        XCTAssertTrue(batch.associationChanged)
        XCTAssertEqual(batch.latestRSSI, -61)
    }

    func testConcurrentBurstSchedulesAtMostOneDelivery() {
        let mailbox = WiFiEventMailbox()
        mailbox.activate(generation: 1)
        let scheduled = LockedCounter()

        DispatchQueue.concurrentPerform(iterations: 20_000) { _ in
            if mailbox.enqueue(.modeChanged, generation: 1) {
                scheduled.increment()
            }
        }

        XCTAssertEqual(scheduled.value, 1)
        XCTAssertEqual(
            mailbox.diagnosticsSnapshot().maximumPendingSignals,
            20_000
        )
    }

    func testCloseDropsPendingAndFutureEvents() {
        let mailbox = WiFiEventMailbox()
        mailbox.activate(generation: 1)

        XCTAssertTrue(mailbox.enqueue(.ssidChanged, generation: 1))
        mailbox.close()

        XCTAssertNil(mailbox.take())
        XCTAssertFalse(mailbox.enqueue(.ssidChanged, generation: 1))
        XCTAssertEqual(mailbox.diagnosticsSnapshot().deliveredBatches, 0)
    }

    func testActivationDropsPendingAndFutureEventsFromTheSupersededGeneration() throws {
        let mailbox = WiFiEventMailbox()
        mailbox.activate(generation: 1)
        XCTAssertTrue(mailbox.enqueue(.connectionInvalidated, generation: 1))

        XCTAssertEqual(
            mailbox.activate(generation: 2)?.connectionInvalidated,
            true
        )

        XCTAssertNil(mailbox.take())
        XCTAssertFalse(mailbox.enqueue(.connectionInterrupted, generation: 1))
        XCTAssertTrue(mailbox.enqueue(.linkQuality(rssi: -61), generation: 2))

        let batch = try XCTUnwrap(mailbox.take())
        XCTAssertEqual(batch.latestRSSI, -61)
        XCTAssertFalse(batch.connectionInterrupted)
        XCTAssertFalse(batch.connectionInvalidated)
        XCTAssertEqual(mailbox.diagnosticsSnapshot().activeGeneration, 2)
    }

    func testProxyCallbackInFlightAcrossActivationCannotEnterTheNewGeneration() {
        let mailbox = WiFiEventMailbox()
        mailbox.activate(generation: 1)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let accepted = LockedBoolean()
        let receiver = BlockingWiFiEventReceiver(
            mailbox: mailbox,
            entered: entered,
            release: release,
            accepted: accepted
        )
        let proxy = CoreWLANEventDelegateProxy(
            target: receiver,
            generation: 1
        )

        DispatchQueue.global().async {
            proxy.clientConnectionInterrupted()
            finished.signal()
        }

        XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)
        mailbox.activate(generation: 2)
        release.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + 1), .success)
        XCTAssertFalse(accepted.value)
        XCTAssertNil(mailbox.take())
    }

    func testProxyInvalidationWaitsForInFlightDeliveryToReachMailbox() {
        let mailbox = WiFiEventMailbox()
        mailbox.activate(generation: 1)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let accepted = LockedBoolean()
        let receiver = BlockingWiFiEventReceiver(
            mailbox: mailbox,
            entered: entered,
            release: release,
            accepted: accepted
        )
        let proxy = CoreWLANEventDelegateProxy(
            target: receiver,
            generation: 1
        )

        DispatchQueue.global().async {
            proxy.clientConnectionInvalidated()
            finished.signal()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)

        let invalidationStarted = DispatchSemaphore(value: 0)
        let invalidationFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            invalidationStarted.signal()
            proxy.invalidate()
            invalidationFinished.signal()
        }
        XCTAssertEqual(
            invalidationStarted.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(
            invalidationFinished.wait(timeout: .now() + 0.5),
            .timedOut,
            "invalidation must wait for an accepted callback to reach the mailbox"
        )

        release.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(invalidationFinished.wait(timeout: .now() + 1), .success)
        XCTAssertTrue(accepted.value)
        XCTAssertEqual(
            mailbox.activate(generation: 2)?.connectionInvalidated,
            true
        )
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func increment() {
        lock.withLock {
            storedValue += 1
        }
    }
}

private final class LockedBoolean: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.withLock { storedValue }
    }

    func set(_ value: Bool) {
        lock.withLock { storedValue = value }
    }
}

private final class BlockingWiFiEventReceiver: WiFiEventReceiving, @unchecked Sendable {
    private let mailbox: WiFiEventMailbox
    private let entered: DispatchSemaphore
    private let release: DispatchSemaphore
    private let accepted: LockedBoolean

    init(
        mailbox: WiFiEventMailbox,
        entered: DispatchSemaphore,
        release: DispatchSemaphore,
        accepted: LockedBoolean
    ) {
        self.mailbox = mailbox
        self.entered = entered
        self.release = release
        self.accepted = accepted
    }

    func receive(_ event: WiFiEventSignal, generation: UInt64) {
        entered.signal()
        _ = release.wait(timeout: .now() + 1)
        accepted.set(mailbox.enqueue(event, generation: generation))
    }
}
