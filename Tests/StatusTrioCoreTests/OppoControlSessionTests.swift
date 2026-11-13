import Foundation
import IOBluetooth
import XCTest

@testable import StatusTrioCore

/// Session-level coverage for `OppoControlSession` and `OppoRFCOMMTransport`.
///
/// This mirrors the Redmi persistent-transport suite: the session is the real
/// one, only the device is faked, so no IOBluetooth device or hardware is
/// touched. The paths that need a *live* `IOBluetoothRFCOMMChannel` — the
/// handshake reaching `ready`, and the read/write exchange — cannot be driven
/// here because that framework class cannot be instantiated or subclassed in a
/// unit test; those stay a manual, on-hardware check (exactly as the Redmi suite
/// leaves them).
///
/// What this pins is the part that was previously entirely untested: the connect
/// timeout, the fail-fast open-error branch, the `stopped`/`close` semantics, and
/// the "one persistent session per address, recreated only after close" contract.

// MARK: - Fakes

/// A device stand-in whose control channel either fails to open immediately
/// (`kIOReturnError`) or reports success but never calls back (`kIOReturnSuccess`,
/// the connect-timeout case). Either way it never touches IOBluetooth.
private final class FakeOppoControlDevice: OppoBluetoothDevice, @unchecked Sendable {
    var addressString: String? { "AA:BB:CC:DD:EE:FF" }

    private let openResult: IOReturn
    private let lock = NSLock()
    private var opens = 0

    init(openResult: IOReturn = kIOReturnError) {
        self.openResult = openResult
    }

    func isConnected() -> Bool { true }
    func cachedControlService() -> IOBluetoothSDPServiceRecord? { nil }
    func queryForControlService() -> Bool { false }

    func openControlChannel(
        id: BluetoothRFCOMMChannelID,
        delegate: IOBluetoothRFCOMMChannelDelegate
    ) -> IOReturn {
        lock.lock()
        opens += 1
        lock.unlock()
        return openResult
    }

    var openCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return opens
    }
}

/// Counts how many sessions the transport hands out, so a reused session and a
/// recreated one are distinguishable without inspecting private state.
private final class CountingOppoSessionFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var creations = 0

    func bump() {
        lock.lock()
        creations += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return creations
    }
}

// MARK: - Tests

final class OppoControlSessionTests: XCTestCase {
    private let address = "AA:BB:CC:DD:EE:FF"

    private func makeTransport(
        device: FakeOppoControlDevice,
        factory: CountingOppoSessionFactory
    ) -> OppoRFCOMMTransport {
        OppoRFCOMMTransport(
            resolveDevice: { _ in device },
            sessionFactory: { resolvedDevice, resolvedAddress in
                factory.bump()
                return OppoControlSession(
                    device: resolvedDevice,
                    address: resolvedAddress,
                    connectTimeoutSeconds: 0.1
                )
            }
        )
    }

    /// A device that "opens" but never completes must surface as
    /// `handshakeTimeout` after the short connect timeout, not hang.
    func testConnectTimeoutFailsWithHandshakeTimeoutInsteadOfHanging() async {
        let device = FakeOppoControlDevice(openResult: kIOReturnSuccess)
        let session = OppoControlSession(
            device: device,
            address: address,
            connectTimeoutSeconds: 0.1
        )

        do {
            _ = try await session.readState()
            XCTFail("expected handshakeTimeout")
        } catch let error as OppoListeningModeError {
            XCTAssertEqual(error, .handshakeTimeout)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertEqual(device.openCount, 1, "the channel open is attempted once")
        session.close()
    }

    /// A rejected `openControlChannel` fails fast with the underlying status,
    /// rather than waiting out the connect timeout.
    func testOpenFailureFailsFastWithChannelConnectionFailed() async {
        let device = FakeOppoControlDevice(openResult: kIOReturnError)
        let session = OppoControlSession(
            device: device,
            address: address,
            connectTimeoutSeconds: 1.0
        )

        do {
            _ = try await session.readState()
            XCTFail("expected channelConnectionFailed")
        } catch let error as OppoListeningModeError {
            XCTAssertEqual(error, .channelConnectionFailed(kIOReturnError))
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        session.close()
    }

    /// An address that resolves to no device fails closed with
    /// `controlServiceNotFound`, without opening anything.
    func testUnknownAddressThrowsControlServiceNotFound() async {
        let transport = OppoRFCOMMTransport(
            resolveDevice: { _ in nil },
            sessionFactory: { device, address in
                OppoControlSession(device: device, address: address)
            }
        )

        do {
            _ = try await transport.state(address: "000000000000")
            XCTFail("expected controlServiceNotFound")
        } catch let error as OppoListeningModeError {
            XCTAssertEqual(error, .controlServiceNotFound)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    /// One persistent session backs repeated requests; only an explicit close
    /// drops it. This is the contract that keeps the control channel held.
    func testPersistentSessionIsReusedAcrossRequestsAndRecreatedAfterClose() async {
        let factory = CountingOppoSessionFactory()
        let device = FakeOppoControlDevice(openResult: kIOReturnError)
        let transport = makeTransport(device: device, factory: factory)

        _ = try? await transport.state(address: address)
        _ = try? await transport.state(address: address)
        XCTAssertEqual(factory.count, 1, "the same session must back repeated requests")

        transport.close(address: address)
        _ = try? await transport.state(address: address)
        XCTAssertEqual(factory.count, 2, "closing drops the session so the next request reconnects")

        transport.closeAll()
    }

    /// `closeAll()` drops every address's session, and is idempotent.
    func testCloseAllDropsEverySession() async {
        let factory = CountingOppoSessionFactory()
        let device = FakeOppoControlDevice(openResult: kIOReturnError)
        let transport = makeTransport(device: device, factory: factory)

        _ = try? await transport.state(address: "11:22:33:44:55:66")
        _ = try? await transport.state(address: "22:33:44:55:66:77")
        XCTAssertEqual(factory.count, 2)

        transport.closeAll()
        _ = try? await transport.state(address: "11:22:33:44:55:66")
        XCTAssertEqual(factory.count, 3, "closeAll must drop the sessions so the next request rebuilds one")

        transport.closeAll()
        transport.closeAll() // idempotent
    }

    /// `close()` while a connect is still pending must release the waiting
    /// request instead of leaving it blocked until the timeout, and the session
    /// must then reject further requests immediately.
    func testCloseReleasesAPendingConnectAndRejectsFurtherRequests() async {
        let device = FakeOppoControlDevice(openResult: kIOReturnSuccess)
        let session = OppoControlSession(
            device: device,
            address: address,
            connectTimeoutSeconds: 2.0
        )

        let pending = Task { try await session.readState() }
        await waitUntil { device.openCount >= 1 }
        session.close()

        do {
            _ = try await pending.value
            XCTFail("expected the pending connect to be cancelled by close()")
        } catch is CancellationError {
            // Expected: close() resumes the waiter with CancellationError.
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        do {
            _ = try await session.readState()
            XCTFail("expected a closed session to reject further requests")
        } catch is CancellationError {
            // Expected: ensureConnected sees stopped and throws CancellationError.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ predicate: @escaping @Sendable () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
