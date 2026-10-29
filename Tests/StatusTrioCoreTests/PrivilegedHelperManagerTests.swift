import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class PrivilegedHelperManagerTests: XCTestCase {
    func testFacadeMapsAsyncReadinessImmediatelyWhenVerificationCompletes() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        service.holdVerification = true
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        let facade = PrivilegedHelperFacade(service: manager)

        XCTAssertFalse(facade.isReady)
        await waitUntil { service.verificationContinuation != nil }

        service.verificationContinuation?.resume()
        await waitUntil { service.verificationContinuation == nil }

        // The publisher must map the new readiness value in the same delivery;
        // no later poll or manual facade refresh may be needed.
        XCTAssertTrue(facade.isReady)
        XCTAssertFalse(facade.requiresApproval)
    }

    func testFacadeMapsApprovalChangeFromPublisherValues() {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service)
        var presentations: [PrivilegedHelperPresentation] = []
        let cancellable = manager.presentationPublisher.sink { presentations.append($0) }
        defer { cancellable.cancel() }

        service.status = .enabled
        manager.refresh()

        // `@Published` emits before assignment. The presentation must reflect
        // the new status in the same delivery, not the old one.
        XCTAssertEqual(presentations.last?.requiresApproval, false)
        XCTAssertEqual(presentations.last?.isEnabled, true)
    }

    func testFacadeMapsApprovalFlagImmediatelyWhenRegistrationNeedsApproval() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = NSError(domain: "SMAppServiceErrorDomain", code: 1)
        let manager = PrivilegedHelperManager(service: service)
        let facade = PrivilegedHelperFacade(service: manager)

        manager.setEnabled(true)

        XCTAssertTrue(facade.requiresApproval)
        XCTAssertFalse(facade.didFailLastOperation)
        XCTAssertNil(facade.lastErrorMessage)
    }

    func testFacadeMapsOperationFailureImmediately() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = NSError(
            domain: "RegistrationFailure",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Registration was rejected."]
        )
        let manager = PrivilegedHelperManager(service: service)
        let facade = PrivilegedHelperFacade(service: manager)

        manager.setEnabled(true)

        XCTAssertTrue(facade.didFailLastOperation)
        XCTAssertEqual(facade.lastErrorMessage, "Registration was rejected.")
    }

    func testReachableHelperIsUsableWhileNativeApprovalStillLags() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.allowsPendingVerification = true
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        await waitUntil { manager.isReady }

        XCTAssertTrue(manager.isReady)
        XCTAssertTrue(manager.requiresApproval)
        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertGreaterThan(service.verificationCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 0)
    }

    func testPendingHelperCanBecomeReachableWithoutANativeStatusChange() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(
            service: service, pollInterval: .milliseconds(20), healthCheckInterval: .milliseconds(40)
        )
        await waitUntil { service.verificationCallCount > 0 }
        XCTAssertGreaterThan(service.verificationCallCount, 0)
        XCTAssertFalse(manager.isReady)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 0)

        service.allowsPendingVerification = true
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertEqual(service.registerCallCount, 0)
    }

    func testActivationRechecksAReachablePendingHelperWithoutRewritingRegistration() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.allowsPendingVerification = true
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        service.allowsPendingVerification = false

        manager.refreshAfterActivation()
        await waitUntil { !manager.isReady }

        XCTAssertFalse(manager.isReady)
        XCTAssertTrue(manager.requiresApproval)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
    }

    func testVerifiedPendingHelperIsNotProbedAtTheApprovalPollFrequency() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.allowsPendingVerification = true
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        let reads = service.verificationCallCount
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(service.verificationCallCount, reads)
    }

    func testPendingHealthCheckStaysFarSlowerThanTheApprovalPoll() {
        // Each pending probe starts the root daemon, which idle-exits about
        // five seconds later. A native status that never leaves pending must
        // not turn that into a continuous daemon restart loop.
        XCTAssertGreaterThanOrEqual(
            PrivilegedHelperManager.defaultPendingHealthCheckInterval, .seconds(30)
        )
    }

    func testUnreachablePendingHelperIsNotProbedOnEveryPoll() async {
        // A native status that never leaves pending must not turn the 2-second
        // approval poll into a probe loop: each probe starts the root daemon.
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(
            service: service, pollInterval: .milliseconds(10), healthCheckInterval: .milliseconds(300)
        )
        await waitUntil { service.verificationCallCount > 0 }
        let probesAfterFirst = service.verificationCallCount
        XCTAssertEqual(probesAfterFirst, 1)

        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(service.verificationCallCount, probesAfterFirst)
        XCTAssertFalse(manager.isReady)
        XCTAssertEqual(manager.status, .requiresApproval)

        await waitUntil { service.verificationCallCount > probesAfterFirst }
        XCTAssertGreaterThan(service.verificationCallCount, probesAfterFirst)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 0)
    }

    func testUserInitiatedReadFailureIsRetriedSoonerThanTheHealthInterval() async {
        // Flipping the helper off and on in System Settings never moves the
        // native status, so the app only learns about it from the forced read
        // it makes when the user comes back. That read can land inside the
        // transition; without a short window it failed and then left the status
        // line on "not verified" for the whole health-check interval, which is
        // what made the same gesture look randomly broken.
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.allowsPendingVerification = true
        let manager = PrivilegedHelperManager(
            service: service,
            pollInterval: .milliseconds(10),
            healthCheckInterval: .seconds(30),
            pendingProbeBackoff: [.milliseconds(30)]
        )
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        let readsWhileReachable = service.verificationCallCount

        // The helper goes away, and the user's gesture is the only signal the
        // app gets: the native status never moves.
        service.allowsPendingVerification = false
        manager.refreshAfterActivation()

        // The failed gesture is retried within its window — far inside the
        // thirty seconds the health timer would otherwise have waited out.
        await waitUntil { service.verificationCallCount > readsWhileReachable + 1 }

        XCTAssertGreaterThanOrEqual(service.verificationCallCount, readsWhileReachable + 2)
        XCTAssertFalse(manager.isReady)
        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 0)
    }

    func testUserInitiatedReadFailureBackoffIsBounded() async {
        // The short window may only spend itself on the gesture that opened it.
        // Once it is used up the steady interval rules again, so a helper that
        // can never be read does not keep starting the root daemon.
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.allowsPendingVerification = true
        let manager = PrivilegedHelperManager(
            service: service,
            pollInterval: .milliseconds(10),
            healthCheckInterval: .seconds(30),
            pendingProbeBackoff: [.milliseconds(20), .milliseconds(20)]
        )
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        service.allowsPendingVerification = false
        manager.refreshAfterActivation()
        // Let the window spend itself, then confirm the reads stop arriving.
        try? await Task.sleep(for: .milliseconds(200))
        let readsAfterWindow = service.verificationCallCount
        try? await Task.sleep(for: .milliseconds(150))

        // The forced read plus both offsets of the window.
        XCTAssertGreaterThanOrEqual(readsAfterWindow, 3)
        XCTAssertLessThanOrEqual(readsAfterWindow, 4)
        XCTAssertEqual(service.verificationCallCount, readsAfterWindow)
        XCTAssertFalse(manager.isReady)
        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 0)
    }

    func testPendingProbeBackoffStaysShortAndBounded() {
        let backoff = PrivilegedHelperManager.defaultPendingProbeBackoff
        XCTAssertFalse(backoff.isEmpty)
        XCTAssertLessThanOrEqual(backoff.count, 4)
        XCTAssertLessThan(
            backoff.reduce(Duration.zero, +),
            PrivilegedHelperManager.defaultPendingHealthCheckInterval
        )
    }

    func testPendingReadinessIsRecheckedEvenWhenNativeStatusNeverChanges() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.allowsPendingVerification = true
        let manager = PrivilegedHelperManager(
            service: service, pollInterval: .milliseconds(5), healthCheckInterval: .milliseconds(40)
        )
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        service.allowsPendingVerification = false
        await waitUntil { !manager.isReady }
        XCTAssertFalse(manager.isReady)
        XCTAssertEqual(manager.status, .requiresApproval)
        service.allowsPendingVerification = true
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 0)
    }

    func testPendingReadReplyAfterOptOutCannotRestoreReadiness() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.allowsPendingVerification = true
        service.holdVerification = true
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        await waitUntil { service.verificationContinuation != nil }
        XCTAssertNotNil(service.verificationContinuation)
        manager.setEnabled(false)
        let reads = service.verificationCallCount
        service.verificationContinuation?.resume()
        await waitUntil { service.verificationContinuation == nil }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(manager.isReady)
        XCTAssertFalse(manager.isHelperResponsive)
        XCTAssertEqual(service.verificationCallCount, reads)
        XCTAssertEqual(service.registerCallCount, 0)
    }

    func testSuccessfulPendingReadStopsRegistrationRetryWindow() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.allowsPendingVerification = true
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(5))
        manager.setEnabled(true)
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        let attempts = service.registerCallCount
        try? await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(service.registerCallCount, attempts)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 0)
    }

    func testOptOutPreservesApprovalAndStopsHelperReads() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        await waitUntil { manager.isReady }
        let reads = service.verificationCallCount

        manager.setEnabled(false)
        manager.refreshAfterActivation()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.isReady)
        XCTAssertFalse(manager.isHelperResponsive)
        XCTAssertEqual(service.status, .enabled)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.verificationCallCount, reads)
    }

    func testRepeatedOptInChangesDoNotRewriteApprovedRegistration() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        await waitUntil { manager.isReady }
        for _ in 0..<5 {
            manager.setEnabled(false)
            XCTAssertFalse(manager.isReady)
            manager.setEnabled(true)
            await waitUntil { manager.isReady }
            XCTAssertTrue(manager.isReady)
        }
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 0)
    }

    func testPermissionDenialBeforeApprovalStatusSettlesShowsOnlyWaiting() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = NSError(domain: "SMAppServiceErrorDomain", code: 1)
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.requiresApproval)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertNil(manager.lastErrorMessage)
        XCTAssertEqual(manager.status, .notRegistered)
    }

    func testPersistentPermissionErrorWithoutPendingRegistrationIsExposedAfterRetries() async {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = NSError(domain: "SMAppServiceErrorDomain", code: 1)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(5))
        manager.setEnabled(true)
        XCTAssertTrue(manager.requiresApproval)
        await waitUntil { service.registerCallCount == 6 }
        await waitUntil { manager.didFailLastOperation }
        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertFalse(manager.requiresApproval)
        XCTAssertNotNil(manager.lastErrorMessage)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(service.registerCallCount, 6)
    }

    func testPendingRegistrationRetriesAfterPermissionArrivesWithoutAnotherToggle() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        manager.setEnabled(true)
        service.registerError = nil
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testRegistrationRetryAlsoRecoversAnUnregisteredTransientFailure() async {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)
        service.registerError = nil
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testOpeningApprovalSettingsStartsANewBoundedRetryWindow() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(5))
        manager.setEnabled(true)
        await waitUntil { service.registerCallCount == 6 }
        let attempts = service.registerCallCount
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(service.registerCallCount, attempts)
        service.registerError = nil
        manager.openLoginItemsSettings()
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        XCTAssertGreaterThan(service.registerCallCount, attempts)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testOptOutCancelsPendingRegistrationRetries() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        manager.setEnabled(true)
        manager.setEnabled(false)
        let attempts = service.registerCallCount
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(service.registerCallCount, attempts)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.requiresApproval)
    }

    func testRegistrationRetryDoesNotHideUnrelatedPermissionErrors() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = NSError(domain: "OtherRegistrationFailure", code: 1)
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertFalse(manager.requiresApproval)
        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertNotNil(manager.lastErrorMessage)
    }

    func testFailedRecoveryRegistrationGetsADelayedRegisterOnlyRetry() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        service.verificationFailuresRemaining = 1
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        await waitUntil { manager.didFailLastOperation }
        service.registerError = nil
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 1)
    }

    func testRecoveryThatRegistersIntoPendingApprovalGetsDelayedRetries() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        service.verificationFailuresRemaining = 1
        service.statusAfterRegister = .requiresApproval
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        await waitUntil { manager.status == .requiresApproval }
        service.statusAfterRegister = .enabled
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 1)
    }

    func testEnabledServiceMustAnswerAReadBeforeItIsApproved() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        XCTAssertFalse(manager.isReady)
        await waitUntil { service.verificationCallCount > 0 && manager.isReady }
        XCTAssertTrue(manager.isReady)
        XCTAssertEqual(service.registerCallCount, 0)
    }

    func testEnabledButUnreachableHelperIsRecovered() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        service.verificationFailuresRemaining = 1
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        await waitUntil { service.recoveryUnregisterCallCount > 0 && manager.isReady }
        XCTAssertTrue(manager.isReady)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 1)
    }

    func testDeniedRegistrationAwaitingApprovalIsNotAnOperationFailure() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        service.statusOnRegistrationFailure = .requiresApproval
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.requiresApproval)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertNil(manager.lastErrorMessage)
    }

    func testFailedHealthRecoveryHasATwoAttemptLimit() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        service.verificationFailuresRemaining = 100
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        await waitUntil { service.verificationCallCount >= 4 }
        let readsAfterExhaustion = service.verificationCallCount
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(service.recoveryUnregisterCallCount, 2)
        XCTAssertEqual(service.verificationCallCount, readsAfterExhaustion)
        XCTAssertFalse(manager.isReady)
        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertTrue(manager.isEnabled)
        service.status = .requiresApproval
        manager.refresh()
        service.status = .enabled
        manager.refresh()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(service.recoveryUnregisterCallCount, 2)
    }

    func testOptOutDuringRecoveryPreventsReregistration() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        service.verificationFailuresRemaining = 1
        service.holdRecoveryUnregister = true
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        await waitUntil { service.recoveryContinuation != nil }
        XCTAssertNotNil(service.recoveryContinuation)
        manager.setEnabled(false)
        service.recoveryContinuation?.resume()
        await waitUntil { service.recoveryContinuation == nil }
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertFalse(manager.isEnabled)
    }

    func testPollDoesNotCancelAnUnregisterThatIsStillCompleting() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        service.verificationFailuresRemaining = 1
        service.holdRecoveryUnregister = true
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        await waitUntil { service.recoveryContinuation != nil }
        service.status = .notRegistered
        try? await Task.sleep(for: .milliseconds(80))
        service.recoveryContinuation?.resume()
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 1)
    }

    func testEnabledHelperIsRecheckedWithoutAUserAction() async {
        // A helper that crashes after a successful verification used to stay
        // "ready" until the user touched the switch: nothing ever read it again.
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(
            service: service,
            pollInterval: .milliseconds(5),
            enabledHealthCheckInterval: .milliseconds(30)
        )
        await waitUntil { manager.isReady }
        let readsAfterReady = service.verificationCallCount

        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertGreaterThanOrEqual(service.verificationCallCount, readsAfterReady + 2)
        XCTAssertTrue(manager.isReady)
        XCTAssertFalse(manager.didFailLastOperation)
        // Re-probing must not churn the registration of a healthy helper.
        XCTAssertEqual(service.recoveryUnregisterCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
    }

    func testSuccessfulRecoveryRestoresTheRecoveryBudget() async {
        // Two unrelated transient failures used to spend the whole budget: every
        // later recovery was refused for the rest of the session because the
        // counter only reset when the user flipped the switch.
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(
            service: service,
            pollInterval: .milliseconds(5),
            enabledHealthCheckInterval: .milliseconds(20)
        )
        await waitUntil { manager.isReady }

        for expected in 1...3 {
            service.verificationFailuresRemaining = 1
            await waitUntil { service.recoveryUnregisterCallCount == expected }
            service.verificationFailuresRemaining = 0
            await waitUntil { manager.isReady }
        }

        XCTAssertEqual(service.recoveryUnregisterCallCount, 3)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertTrue(manager.isReady)
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(1)
        while !predicate(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testVerifiedHelperIsNotKeptAliveByStatusPolling() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        await waitUntil { manager.isReady }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(service.verificationCallCount, 1)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 0)
    }

    func testActivationRetryWhileWaitingIsBoundedAndDoesNotUnregister() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(5))
        for _ in 0..<10 { manager.refreshAfterActivation() }
        await waitUntil { service.registerCallCount == 5 }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(service.registerCallCount, 5)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertGreaterThan(service.verificationCallCount, 0)
        XCTAssertTrue(manager.requiresApproval)
        XCTAssertFalse(manager.didFailLastOperation)
    }

    func testRefreshDoesNotUnregisterApprovalThatArrivedBeforeThePoll() {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service)
        service.status = .enabled
        service.registerError = TestFailure.registration

        manager.refresh()

        XCTAssertEqual(manager.status, .enabled)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertFalse(manager.didFailLastOperation)
    }

    func testOptOutReadsButPreservesRegistrationThatArrivedBeforeThePoll() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        let manager = PrivilegedHelperManager(service: service)
        service.registerError = TestFailure.registration
        manager.setEnabled(true)
        service.status = .enabled

        manager.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.status, .enabled)
        XCTAssertEqual(manager.status, .enabled)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.isReady)
    }

    func testOptOutBeforeVerificationStopsHelperContact() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        manager.setEnabled(false)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .enabled)
        XCTAssertEqual(service.verificationCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testStatusAndAvailabilityReflectTheService() {
        let enabled = PrivilegedHelperManager(service: FakePrivilegedHelperService(status: .enabled))
        XCTAssertEqual(enabled.status, .enabled)
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertTrue(enabled.isAvailable)
        XCTAssertFalse(enabled.requiresApproval)

        let notRegistered = PrivilegedHelperManager(
            service: FakePrivilegedHelperService(status: .notRegistered)
        )
        XCTAssertFalse(notRegistered.isEnabled)
        XCTAssertTrue(notRegistered.isAvailable)
    }

    func testUnsupportedBuildDisablesTheToggle() {
        let service = FakePrivilegedHelperService(status: .notRegistered, isSupported: false)
        let manager = PrivilegedHelperManager(service: service)

        XCTAssertFalse(manager.isAvailable)

        manager.setEnabled(true)
        XCTAssertEqual(service.registerCallCount, 0)
    }

    func testSystemNotFoundIsTreatedAsNotRegistered() {
        // macOS answers `notFound` for a daemon that has never registered.
        XCTAssertEqual(SystemPrivilegedHelperService.status(for: .notFound), .notRegistered)
        XCTAssertEqual(SystemPrivilegedHelperService.status(for: .notRegistered), .notRegistered)
        XCTAssertEqual(SystemPrivilegedHelperService.status(for: .enabled), .enabled)
        XCTAssertEqual(
            SystemPrivilegedHelperService.status(for: .requiresApproval),
            .requiresApproval
        )
    }

    func testEnablingRegistersAndPublishesEnabled() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        let manager = PrivilegedHelperManager(service: service)

        manager.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(manager.status, .enabled)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertFalse(manager.didFailLastOperation)
    }

    func testOptOutKeepsRegistrationButMakesTheFeatureUnavailable() {
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(service: service)

        manager.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(manager.status, .enabled)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.isReady)
    }

    func testReenablingWhileWaitingRetriesRegistration() {
        // A LaunchDaemon needs an administrator to approve it before launchd
        // starts it, so `requiresApproval` is an expected intermediate state.
        // Flicking the switch on again re-asks, because the approval the system
        // is waiting for arrives outside the app.
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let manager = PrivilegedHelperManager(service: service)

        manager.setEnabled(true)

        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertTrue(manager.requiresApproval)
        XCTAssertEqual(service.registerCallCount, 1)

        manager.setEnabled(true)
        XCTAssertEqual(service.registerCallCount, 2)
    }

    func testOptOutPreservesAPendingRegistrationWithoutShowingApprovalWarning() {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service)
        XCTAssertTrue(manager.isEnabled)

        manager.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertFalse(manager.requiresApproval)
    }

    func testRegistrationFailureIsReportedAndLeavesStatusUnchanged() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)

        manager.setEnabled(true)

        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .notRegistered)
        // The switch follows what the user asked for; the banner and the note
        // underneath explain why the helper is not working yet.
        XCTAssertTrue(manager.isEnabled)
    }

    func testLaterSuccessfulOperationClearsTheFailureFlag() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)

        service.registerError = nil
        manager.setEnabled(true)

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .enabled)
    }

    func testRefreshObservesPendingApprovalWithoutRewritingRegistration() async {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)

        service.status = .requiresApproval
        manager.refresh()
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)

        service.status = .enabled
        manager.refresh()
        await waitUntil { manager.isReady }
        XCTAssertTrue(manager.isReady)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertNil(manager.lastErrorMessage)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testRefreshClearsAFailureOnceTheDaemonIsApproved() async {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)

        service.status = .enabled
        manager.refresh()
        await waitUntil { manager.isReady }

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertTrue(manager.isReady)
    }

    func testRefreshKeepsAFailureThatIsStillUnsettled() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)

        manager.refresh()

        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .notRegistered)
    }

    func testOptOutClearsAnUnsettledRegistrationFailure() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)
        manager.setEnabled(false)

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertNil(manager.lastErrorMessage)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testRefreshWithoutAFailureLeavesTheFlagClear() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        let manager = PrivilegedHelperManager(service: service)

        service.status = .enabled
        manager.refresh()

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .enabled)
    }

    func testPendingRegistrationIsPickedUpWhenTheSystemApprovesIt() async {
        // macOS posts nothing when the user enables the app under System
        // Settings › Login Items, so the registration that is waiting has to be
        // watched — and watched without touching it, because unregistering and
        // re-registering in a loop leaves the item flapping.
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        XCTAssertTrue(manager.isEnabled)

        service.status = .enabled

        let deadline = Date().addingTimeInterval(5)
        while !manager.isReady, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(manager.status, .enabled)
        XCTAssertTrue(manager.isReady)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testPendingRegistrationIsNotRewrittenByThePoll() async {
        // The flapping regression: a poll that unregisters and re-registers the
        // pending item made the status alternate between `requiresApproval` and
        // `notRegistered` every couple of seconds.
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))

        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testFeatureOptOutStopsWatchingTheSystem() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))

        manager.setEnabled(false)
        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertFalse(manager.isEnabled)

        service.status = .enabled
        try? await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(manager.status, .requiresApproval)
    }

    func testOpenLoginItemsSettingsIsForwardedToTheService() {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service)

        manager.openLoginItemsSettings()

        XCTAssertEqual(service.openLoginItemsCallCount, 1)
    }

    func testEnabledBindingReadsAndWritesManagerState() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        let manager = PrivilegedHelperManager(service: service)

        XCTAssertFalse(manager.isEnabledBinding.wrappedValue)

        manager.isEnabledBinding.wrappedValue = true
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertTrue(manager.isEnabledBinding.wrappedValue)
    }

    private enum TestFailure: Error {
        case registration
        case unregistration
    }
}

@MainActor
final class FakePrivilegedHelperService: PrivilegedHelperServicing {
    var status: PrivilegedHelperStatus
    var statusAfterRegister: PrivilegedHelperStatus?
    var registerError: Error?
    var unregisterError: Error?
    var statusOnRegistrationFailure: PrivilegedHelperStatus?
    var verificationFailuresRemaining = 0
    var allowsPendingVerification = false
    var holdVerification = false
    var verificationContinuation: CheckedContinuation<Void, Never>?
    var holdRecoveryUnregister = false
    var recoveryContinuation: CheckedContinuation<Void, any Error>?
    private(set) var verificationCallCount = 0
    private(set) var recoveryUnregisterCallCount = 0
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openLoginItemsCallCount = 0
    let isSupported: Bool

    init(status: PrivilegedHelperStatus, isSupported: Bool = true) {
        self.status = status
        self.isSupported = isSupported
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            if let statusOnRegistrationFailure { status = statusOnRegistrationFailure }
            throw registerError
        }
        status = statusAfterRegister ?? .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = .notRegistered
    }

    func openLoginItemsSettings() {
        openLoginItemsCallCount += 1
    }

    func verifyConnection() async throws {
        verificationCallCount += 1
        if holdVerification {
            await withCheckedContinuation { verificationContinuation = $0 }
            verificationContinuation = nil
        }
        if status == .requiresApproval, !allowsPendingVerification {
            throw NSError(domain: "XPCProbe", code: 4099)
        }
        if verificationFailuresRemaining > 0 {
            verificationFailuresRemaining -= 1
            throw NSError(domain: "XPCProbe", code: 4099)
        }
    }

    func unregisterForRecovery() async throws {
        recoveryUnregisterCallCount += 1
        if holdRecoveryUnregister {
            try await withCheckedThrowingContinuation { recoveryContinuation = $0 }
            recoveryContinuation = nil
        }
        try unregister()
    }
}
