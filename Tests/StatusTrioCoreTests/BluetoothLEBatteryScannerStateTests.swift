import Foundation
import Testing
@testable import StatusTrioCore

struct BluetoothLEBatteryScannerStateTests {
    @Test func currentFormalNameReplacesTemporaryAdvertisedName() {
        #expect(BluetoothLEBatteryNamePolicy.resolvedName(
            formalName: "Renamed iPhone",
            advertisedName: "Temporary-7F2A"
        ) == "Renamed iPhone")
        #expect(BluetoothLEBatteryNamePolicy.resolvedName(
            formalName: "  ",
            advertisedName: "Temporary-7F2A"
        ).isEmpty)
    }
    @Test(arguments: [false, true])
    func cancellingInFlightAttemptThrottlesReauthorization(stopping: Bool) {
        let now = Date()
        let id = UUID(), queuedOnly = UUID()
        var policy = BluetoothLEBatteryScanPolicy()
        _ = policy.beginScan(at: now, manual: true)
        _ = policy.enqueueCandidate(id, at: now)
        _ = policy.startQueuedConnections()
        _ = policy.enqueueCandidate(queuedOnly, at: now)
        if stopping { policy.stop() } else { policy.removeCandidates([id, queuedOnly]) }
        _ = policy.beginScan(at: now.addingTimeInterval(1), manual: true)
        let immediateRetry = policy.enqueueCandidate(id, at: now.addingTimeInterval(1))
        let queuedRetry = policy.enqueueCandidate(queuedOnly, at: now.addingTimeInterval(1))
        #expect(!immediateRetry)
        #expect(queuedRetry)
        _ = policy.beginScan(at: now.addingTimeInterval(61), manual: true)
        let afterCooldown = policy.enqueueCandidate(id, at: now.addingTimeInterval(61))
        #expect(afterCooldown)
    }
    @Test func retryCooldownSurvivesDemandStopAndConnectionsAreBounded() {
        let now = Date(timeIntervalSince1970: 5000)
        let ids = (0..<3).map { _ in UUID() }
        var policy = BluetoothLEBatteryScanPolicy()
        let started = policy.beginScan(at: now, manual: true)
        #expect(started)
        for id in ids {
            let queued = policy.enqueueCandidate(id, at: now)
            #expect(queued)
        }
        let firstConnections = policy.startQueuedConnections()
        let nextConnections = policy.startQueuedConnections()
        #expect(firstConnections.count == 2)
        #expect(nextConnections.isEmpty)
        policy.completeConnection(ids[0], succeeded: false, at: now)
        policy.stop()
        let restarted = policy.beginScan(at: now.addingTimeInterval(1), manual: true)
        #expect(restarted)
        let retried = policy.enqueueCandidate(ids[0], at: now.addingTimeInterval(1))
        #expect(!retried)
    }

    /// A device that never answers must not be retried on the same minute
    /// forever: each consecutive failure earns a longer cooldown, and after the
    /// budget runs out automatic scans leave it alone. This is the course the
    /// issue `#152` report follows — a declined pairing prompt that kept
    /// coming back about once a minute.
    @Test func consecutiveFailuresBackOffAndThenStopAutomaticRetries() {
        let start = Date(timeIntervalSince1970: 7_000)
        let id = UUID()
        var policy = BluetoothLEBatteryScanPolicy()

        let began = policy.beginScan(at: start, manual: true)
        let queued = policy.enqueueCandidate(id, at: start)
        let connections = policy.startQueuedConnections()
        #expect(began)
        #expect(queued)
        #expect(connections == [id])
        policy.completeConnection(id, succeeded: false, at: start)
        #expect(policy.suspendedRetryIDs.isEmpty)

        // First failure: the original one-minute cooldown still applies.
        let earlyScan = policy.beginScan(at: start.addingTimeInterval(59), manual: true)
        let earlyEnqueue = policy.enqueueCandidate(id, at: start.addingTimeInterval(59))
        #expect(earlyScan)
        #expect(!earlyEnqueue)
        let retryScan = policy.beginScan(at: start.addingTimeInterval(61), manual: true)
        let retryEnqueue = policy.enqueueCandidate(id, at: start.addingTimeInterval(61))
        #expect(retryScan)
        #expect(retryEnqueue)
        #expect(policy.startQueuedConnections() == [id])
        policy.completeConnection(id, succeeded: false, at: start.addingTimeInterval(61))
        #expect(policy.suspendedRetryIDs.isEmpty)

        // Second failure: the wait grows instead of repeating the minute.
        let fiveMinuteScan = policy.beginScan(at: start.addingTimeInterval(300), manual: true)
        let fiveMinuteEnqueue = policy.enqueueCandidate(id, at: start.addingTimeInterval(300))
        #expect(fiveMinuteScan)
        #expect(!fiveMinuteEnqueue)
        let afterFiveMinutes = policy.beginScan(at: start.addingTimeInterval(362), manual: true)
        let afterFiveMinuteEnqueue = policy.enqueueCandidate(id, at: start.addingTimeInterval(362))
        #expect(afterFiveMinutes)
        #expect(afterFiveMinuteEnqueue)
        #expect(policy.startQueuedConnections() == [id])
        policy.completeConnection(id, succeeded: false, at: start.addingTimeInterval(362))

        // Third failure: out of budget. No later scan re-enqueues it.
        #expect(policy.suspendedRetryIDs == [id])
        _ = policy.beginScan(at: start.addingTimeInterval(20_000), manual: true)
        let laterEnqueue = policy.enqueueCandidate(id, at: start.addingTimeInterval(20_000))
        #expect(!laterEnqueue)
        _ = policy.beginScan(at: start.addingTimeInterval(200_000), manual: true)
        let muchLaterEnqueue = policy.enqueueCandidate(id, at: start.addingTimeInterval(200_000))
        #expect(!muchLaterEnqueue)
    }

    @Test func oneSuccessfulSessionClearsTheFailureStreak() {
        let start = Date(timeIntervalSince1970: 8_000)
        let id = UUID()
        var policy = BluetoothLEBatteryScanPolicy()

        _ = policy.beginScan(at: start, manual: true)
        _ = policy.enqueueCandidate(id, at: start)
        _ = policy.startQueuedConnections()
        policy.completeConnection(id, succeeded: false, at: start)
        policy.completeConnection(id, succeeded: false, at: start)

        _ = policy.beginScan(at: start.addingTimeInterval(301), manual: true)
        let retried = policy.enqueueCandidate(id, at: start.addingTimeInterval(301))
        #expect(retried)
        _ = policy.startQueuedConnections()
        policy.completeConnection(id, succeeded: true, at: start.addingTimeInterval(301))

        // A failure after the success starts the escalation over at one minute.
        _ = policy.beginScan(at: start.addingTimeInterval(362), manual: true)
        let failingAgain = policy.enqueueCandidate(id, at: start.addingTimeInterval(362))
        #expect(failingAgain)
        _ = policy.startQueuedConnections()
        policy.completeConnection(id, succeeded: false, at: start.addingTimeInterval(362))
        #expect(policy.suspendedRetryIDs.isEmpty)

        _ = policy.beginScan(at: start.addingTimeInterval(400), manual: true)
        let tooSoon = policy.enqueueCandidate(id, at: start.addingTimeInterval(400))
        #expect(!tooSoon)
        _ = policy.beginScan(at: start.addingTimeInterval(423), manual: true)
        let oneMinuteRetry = policy.enqueueCandidate(id, at: start.addingTimeInterval(423))
        #expect(oneMinuteRetry)
    }

    @Test func explicitRefreshResumesASuspendedDevice() {
        let start = Date(timeIntervalSince1970: 9_000)
        let id = UUID()
        var policy = BluetoothLEBatteryScanPolicy()

        for offset in 0..<3 {
            let now = start.addingTimeInterval(Double(offset) * 3_600)
            _ = policy.beginScan(at: now, manual: true)
            let queued = policy.enqueueCandidate(id, at: now)
            #expect(queued)
            _ = policy.startQueuedConnections()
            policy.completeConnection(id, succeeded: false, at: now)
        }
        #expect(policy.suspendedRetryIDs == [id])
        _ = policy.beginScan(at: start.addingTimeInterval(30_000), manual: true)
        let automaticRetry = policy.enqueueCandidate(id, at: start.addingTimeInterval(30_000))
        #expect(!automaticRetry)

        policy.resumeSuspendedRetries()
        #expect(policy.suspendedRetryIDs.isEmpty)
        let afterResume = policy.enqueueCandidate(id, at: start.addingTimeInterval(30_000))
        #expect(afterResume)
    }

    @Test func staleCancellationCannotRemoveNewSession() {
        let id = UUID(), oldSession = UUID(), current = UUID()
        var gate = NearbyBLESessionCancellationGate()
        let began = gate.begin(id, session: current)
        #expect(began)
        let retired = gate.retire(id, session: oldSession)
        #expect(!retired)
        #expect(gate.isCurrent(id, session: current))
    }
    @Test func passiveDiscoveryKeepsScanCadenceWithoutAnyConnectionQueue() {
        let start = Date(timeIntervalSince1970: 1_000)
        var policy = BluetoothLEBatteryScanPolicy()

        #expect(BluetoothLEBatteryScanPolicy.scanWindow == .seconds(5))
        #expect(BluetoothLEBatteryScanPolicy.automaticScanInterval == 60)
        let firstScan = policy.beginScan(at: start, manual: false)
        let earlyAutomaticScan = policy.beginScan(at: start.addingTimeInterval(59), manual: false)
        let manualRefresh = policy.beginScan(at: start.addingTimeInterval(59), manual: true)
        #expect(firstScan)
        #expect(!earlyAutomaticScan)
        #expect(manualRefresh)
    }

    @Test func automaticDiscoveryRefreshContinuesWithNoReadPermits() {
        let start = Date(timeIntervalSince1970: 3_000)
        var policy = BluetoothLEBatteryScanPolicy()
        let initialScan = policy.beginScan(at: start, manual: true)
        #expect(initialScan)

        let discoveryOnlyRefresh = policy.beginAutomaticScan(at: start.addingTimeInterval(60), isRunning: true)
        let stoppedRefresh = policy.beginAutomaticScan(at: start.addingTimeInterval(120), isRunning: false)
        #expect(discoveryOnlyRefresh)
        #expect(!stoppedRefresh)
    }

    @Test func initialAndOngoingReadsHaveDifferentVisibilityRequirements() {
        let visible = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let initial = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let hidden = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let initialReadIDs = BluetoothLEReadDemand.permittedIDs(
            visibleIDs: [visible], initialCandidateIDs: [initial, hidden],
            allowsInitialReads: true, hiddenIDs: [hidden]
        )
        let ongoingReadIDs = BluetoothLEReadDemand.permittedIDs(
            visibleIDs: [visible], initialCandidateIDs: [initial],
            allowsInitialReads: false, hiddenIDs: []
        )

        #expect(initialReadIDs == [visible, initial])
        #expect(ongoingReadIDs == [visible])
    }

    @Test func initialValidationRequiresEnabledSurfaceAndExcludesOnlyHiddenCandidates() {
        let candidate = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
        let hidden = UUID(uuidString: "00000000-0000-0000-0000-000000000112")!
        let allowed = BluetoothLEInitialReadPolicy.permittedCandidateIDs(
            enabled: true, batteryLevelsEnabled: true, hasActiveDiscoverySurface: true,
            showsDeviceList: true, candidateIDs: [candidate, hidden], hiddenIDs: [hidden]
        )
        let batteryOff = BluetoothLEInitialReadPolicy.permittedCandidateIDs(
            enabled: true, batteryLevelsEnabled: false, hasActiveDiscoverySurface: true,
            showsDeviceList: true, candidateIDs: [candidate], hiddenIDs: []
        )
        let noSurface = BluetoothLEInitialReadPolicy.permittedCandidateIDs(
            enabled: true, batteryLevelsEnabled: true, hasActiveDiscoverySurface: false,
            showsDeviceList: true, candidateIDs: [candidate], hiddenIDs: []
        )

        #expect(allowed == [candidate])
        #expect(batteryOff.isEmpty)
        #expect(noSurface.isEmpty)
    }

    @Test func initialAttemptSuppressionExpiresAfterCooldownOrVerifiedRowLifetime() {
        let now = Date(timeIntervalSince1970: 4_000)
        let failedExpiry = BluetoothLEInitialReadPolicy.attemptSuppressionExpiry(
            attemptedAt: now, succeeded: false, verifiedAt: nil
        )
        let successExpiry = BluetoothLEInitialReadPolicy.attemptSuppressionExpiry(
            attemptedAt: now, succeeded: true, verifiedAt: now.addingTimeInterval(1)
        )

        #expect(failedExpiry == now.addingTimeInterval(60))
        #expect(successExpiry == now.addingTimeInterval(1 + BluetoothLEBatteryScanPolicy.resultLifetime))
        #expect(BluetoothLEInitialReadPolicy.shouldSuppressInitialRead(until: failedExpiry, now: failedExpiry.addingTimeInterval(0.001)) == false)
        #expect(BluetoothLEInitialReadPolicy.shouldSuppressInitialRead(until: successExpiry, now: successExpiry.addingTimeInterval(0.001)) == false)
    }

    @Test func stopInvalidatesCallbacksFromThePreviousPassiveScan() {
        var policy = BluetoothLEBatteryScanPolicy()
        let started = policy.beginScan(at: Date(timeIntervalSince1970: 2_000), manual: true)
        let oldGeneration = policy.generation

        policy.stop()

        #expect(started)
        #expect(!policy.acceptsCallback(from: oldGeneration))
    }
}
