import CoreWLAN
import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class WiFiClassifierTests: XCTestCase {
    func testPowerOffWinsEveryOtherSignal() {
        let input = makeInput(
            powerOn: false,
            serviceActive: true,
            mode: .station,
            pathSatisfied: true,
            pathUsesWiFi: true,
            pathExpensive: true,
            sharingActive: true
        )

        XCTAssertEqual(WiFiClassifier.classify(input), .off)
    }

    func testInactiveServiceWinsSharingAndPathSignals() {
        let input = makeInput(
            powerOn: true,
            serviceActive: false,
            mode: .ibss,
            pathSatisfied: true,
            pathUsesWiFi: true,
            pathExpensive: true,
            sharingActive: true
        )

        XCTAssertEqual(WiFiClassifier.classify(input), .notAssociated)
    }

    func testSharingWinsTemporaryAndPathSignals() {
        let input = makeInput(
            powerOn: true,
            serviceActive: true,
            mode: .ibss,
            pathSatisfied: false,
            pathUsesWiFi: true,
            pathExpensive: true,
            sharingActive: true
        )

        XCTAssertEqual(WiFiClassifier.classify(input), .shared)
    }

    func testIBSSWinsExpensiveAndUnsatisfiedPathSignals() {
        let input = makeInput(
            powerOn: true,
            serviceActive: true,
            mode: .ibss,
            pathSatisfied: false,
            pathUsesWiFi: true,
            pathExpensive: true,
            sharingActive: false
        )

        XCTAssertEqual(WiFiClassifier.classify(input), .temporary)
    }

    func testExpensiveSatisfiedWiFiPathIsHotspot() {
        let input = makeInput(
            powerOn: true,
            serviceActive: true,
            mode: .station,
            pathSatisfied: true,
            pathUsesWiFi: true,
            pathExpensive: true,
            sharingActive: false
        )

        XCTAssertEqual(WiFiClassifier.classify(input), .hotspot)
    }

    func testExpensiveUnsatisfiedPathIsNoInternet() {
        let input = makeInput(
            powerOn: true,
            serviceActive: true,
            mode: .station,
            pathSatisfied: false,
            pathUsesWiFi: true,
            pathExpensive: true,
            sharingActive: false
        )

        XCTAssertEqual(WiFiClassifier.classify(input), .noInternet)
    }

    func testUnsatisfiedPathIsNoInternet() {
        let input = makeInput(
            powerOn: true,
            serviceActive: true,
            mode: .station,
            pathSatisfied: false,
            pathUsesWiFi: true,
            pathExpensive: false,
            sharingActive: false
        )

        XCTAssertEqual(WiFiClassifier.classify(input), .noInternet)
    }

    func testSatisfiedOrdinaryWiFiPathIsConnected() {
        let input = makeInput(
            powerOn: true,
            serviceActive: true,
            mode: .station,
            pathSatisfied: true,
            pathUsesWiFi: true,
            pathExpensive: false,
            sharingActive: false
        )

        XCTAssertEqual(WiFiClassifier.classify(input), .connected)
    }

    func testUnknownPathFallsBackToConnectedWhenServiceIsActive() {
        let input = makeInput(
            powerOn: true,
            serviceActive: true,
            mode: .station,
            pathSatisfied: nil,
            pathUsesWiFi: true,
            pathExpensive: true,
            sharingActive: false
        )

        XCTAssertEqual(WiFiClassifier.classify(input), .connected)
    }

    func testUnknownModeFallsBackToConnectedWhenPathIsSatisfied() {
        let input = makeInput(
            powerOn: true,
            serviceActive: true,
            mode: .unknown,
            pathSatisfied: true,
            pathUsesWiFi: true,
            pathExpensive: false,
            sharingActive: false
        )

        XCTAssertEqual(WiFiClassifier.classify(input), .connected)
    }

    func testUnknownModeFallsBackToNoInternetWhenPathIsUnsatisfied() {
        let input = makeInput(
            powerOn: true,
            serviceActive: true,
            mode: .unknown,
            pathSatisfied: false,
            pathUsesWiFi: true,
            pathExpensive: false,
            sharingActive: false
        )

        XCTAssertEqual(WiFiClassifier.classify(input), .noInternet)
    }

    func testExpensiveNonWiFiPathDoesNotBecomeHotspot() {
        let input = makeInput(
            powerOn: true,
            serviceActive: true,
            mode: .station,
            pathSatisfied: true,
            pathUsesWiFi: false,
            pathExpensive: true,
            sharingActive: false
        )

        XCTAssertEqual(WiFiClassifier.classify(input), .connected)
    }

    func testHostAPWithoutConfirmedSharingFallsBackToConnected() {
        let input = makeInput(
            powerOn: true,
            serviceActive: true,
            mode: .hostAP,
            pathSatisfied: true,
            pathUsesWiFi: true,
            pathExpensive: false,
            sharingActive: false
        )

        XCTAssertEqual(WiFiClassifier.classify(input), .connected)
    }

    func testStartWithDefaultUnknownPathPublishesConnectedForAssociatedWiFi() async {
        let reader = FakeWiFiSystemReader(result: makeReading(mode: .station, rssi: -52))
        let sharingDetector = FakeInternetSharingDetector(result: false)
        let eventMonitor = FakeWiFiEventMonitor()
        let pathMonitor = FakeWiFiPathMonitor()
        let monitor = makeMonitor(
            reader: reader,
            sharingDetector: sharingDetector,
            eventMonitor: eventMonitor,
            pathMonitor: pathMonitor
        )
        var iterator = monitor.updates.makeAsyncIterator()

        monitor.start()
        let status = await iterator.next()

        XCTAssertEqual(status?.state, .connected)
        XCTAssertNotEqual(status?.state, .noInternet)
        monitor.stop()
    }

    func testRefreshPublishesConnectedReadingWithRSSI() async {
        let reader = FakeWiFiSystemReader(result: makeReading(mode: .station, rssi: -52))
        let sharingDetector = FakeInternetSharingDetector(result: false)
        let monitor = makeMonitor(reader: reader, sharingDetector: sharingDetector)
        var iterator = monitor.updates.makeAsyncIterator()

        monitor.refresh()

        let status = await iterator.next()
        XCTAssertEqual(status, WiFiStatus(state: .connected, rssi: -52))
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(sharingDetector.callCount, 1)
    }

    func testSSIDReadsOnlyWhenDetailsAreVisible() async {
        let reader = FakeWiFiSystemReader(result: makeReading(ssid: "Office"))
        let authorizer = FakeWiFiNameAuthorizer(access: .authorized)
        let monitor = makeMonitor(reader: reader, nameAuthorizer: authorizer)
        monitor.setDetailsVisible(false)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()

        let hidden = await iterator.next()
        XCTAssertNil(hidden?.ssid)
        XCTAssertEqual(reader.lastIncludeSSID, false)

        monitor.setDetailsVisible(true)
        monitor.refresh()
        let visible = await iterator.next()
        XCTAssertEqual(visible?.ssid, "Office")
        XCTAssertEqual(reader.lastIncludeSSID, true)

        monitor.setDetailsVisible(false)
        let hiddenAgain = await iterator.next()
        XCTAssertNil(hiddenAgain?.ssid)
        XCTAssertEqual(reader.lastIncludeSSID, false)
        monitor.stop()
    }

    func testRefreshPublishesNormalizedSSIDWhenAuthorized() async {
        let reader = FakeWiFiSystemReader(
            result: makeReading(mode: .station, rssi: -52, ssid: "  Studio Wi-Fi  ")
        )
        let nameAuthorizer = FakeWiFiNameAuthorizer(access: .authorized)
        let monitor = makeMonitor(reader: reader, nameAuthorizer: nameAuthorizer)
        var iterator = monitor.updates.makeAsyncIterator()

        monitor.refresh()

        let status = await iterator.next()
        XCTAssertEqual(status?.ssid, "Studio Wi-Fi")
        XCTAssertEqual(status?.nameAccess, .authorized)
    }

    func testRefreshNormalizesBlankSSIDToNil() async {
        let reader = FakeWiFiSystemReader(result: makeReading(ssid: "   "))
        let nameAuthorizer = FakeWiFiNameAuthorizer(access: .authorized)
        let monitor = makeMonitor(reader: reader, nameAuthorizer: nameAuthorizer)
        var iterator = monitor.updates.makeAsyncIterator()

        monitor.refresh()

        let status = await iterator.next()
        XCTAssertNil(status?.ssid)
    }

    func testStartDoesNotRequestNameAccess() {
        let reader = FakeWiFiSystemReader(result: makeReading())
        let nameAuthorizer = FakeWiFiNameAuthorizer()
        let monitor = makeMonitor(reader: reader, nameAuthorizer: nameAuthorizer)

        monitor.start()

        XCTAssertEqual(nameAuthorizer.requestCount, 0)
        monitor.stop()
    }

    func testRequestNameAccessStopsAfterPermissionIsDenied() {
        let reader = FakeWiFiSystemReader(result: makeReading())
        let nameAuthorizer = FakeWiFiNameAuthorizer()
        let monitor = makeMonitor(reader: reader, nameAuthorizer: nameAuthorizer)
        monitor.start()

        monitor.requestNameAccess()
        nameAuthorizer.setAccess(.denied)
        monitor.requestNameAccess()

        XCTAssertEqual(nameAuthorizer.requestCount, 1)
        monitor.stop()
    }

    func testAuthorizationChangeRefreshesAndPublishesSSID() async {
        let reader = FakeWiFiSystemReader(result: makeReading(ssid: "Home"))
        let nameAuthorizer = FakeWiFiNameAuthorizer()
        let monitor = makeMonitor(reader: reader, nameAuthorizer: nameAuthorizer)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        let initialStatus = await iterator.next()

        nameAuthorizer.setAccess(.authorized)
        let authorizedStatus = await iterator.next()

        XCTAssertNil(initialStatus?.ssid)
        XCTAssertEqual(initialStatus?.nameAccess, .notDetermined)
        XCTAssertEqual(authorizedStatus?.ssid, "Home")
        XCTAssertEqual(authorizedStatus?.nameAccess, .authorized)
        monitor.stop()
    }

    func testRefreshUsesInternetSharingDetection() async {
        let reader = FakeWiFiSystemReader(result: makeReading(mode: .station, rssi: -48))
        let sharingDetector = FakeInternetSharingDetector(result: true)
        let monitor = makeMonitor(reader: reader, sharingDetector: sharingDetector)
        var iterator = monitor.updates.makeAsyncIterator()

        monitor.refresh()

        let status = await iterator.next()
        XCTAssertEqual(status, WiFiStatus(state: .shared, rssi: -48))
    }

    func testUncertainSharingFallsBackToOrdinaryState() async {
        let reader = FakeWiFiSystemReader(result: makeReading(mode: .station, rssi: -48))
        let sharingDetector = FakeInternetSharingDetector(result: nil)
        let monitor = makeMonitor(reader: reader, sharingDetector: sharingDetector)
        var iterator = monitor.updates.makeAsyncIterator()

        monitor.refresh()

        let status = await iterator.next()
        XCTAssertEqual(status, WiFiStatus(state: .connected, rssi: -48))
    }

    func testRSSINormalization() async {
        let reader = FakeWiFiSystemReader(result: nil)
        let monitor = makeMonitor(reader: reader)
        var iterator = monitor.updates.makeAsyncIterator()
        let cases: [(input: Int?, expected: Int?)] = [
            (0, nil),
            (-71, -71),
            (nil, nil)
        ]

        for testCase in cases {
            reader.result = makeReading(rssi: testCase.input)
            monitor.refresh()
            let status = await iterator.next()
            XCTAssertEqual(status?.rssi, testCase.expected)
        }
    }

    func testUnavailableReadingPublishesUnavailable() async {
        let reader = FakeWiFiSystemReader(result: nil)
        let sharingDetector = FakeInternetSharingDetector(result: true)
        let monitor = makeMonitor(reader: reader, sharingDetector: sharingDetector)
        var iterator = monitor.updates.makeAsyncIterator()

        monitor.refresh()

        let status = await iterator.next()
        XCTAssertEqual(status, .placeholder)
        XCTAssertEqual(sharingDetector.callCount, 0)
    }

    func testUnavailableReadingRetainsLastValidStatusBeforeStaleInterval() async {
        let clock = ManualWiFiClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
        let reader = FakeWiFiSystemReader(result: makeReading(mode: .station, rssi: -50))
        let monitor = makeMonitor(reader: reader, clock: clock)
        var iterator = monitor.updates.makeAsyncIterator()

        monitor.refresh()
        let first = await iterator.next()

        reader.result = nil
        clock.advance(by: 29)
        monitor.refresh()
        let retainedBeforeBoundary = await iterator.next()

        clock.advance(by: 1)
        monitor.refresh()
        let retainedAtBoundary = await iterator.next()

        XCTAssertEqual(first, WiFiStatus(state: .connected, rssi: -50))
        XCTAssertEqual(retainedBeforeBoundary, first)
        XCTAssertEqual(retainedAtBoundary, first)
    }

    func testUnavailableReadingPublishesUnavailableAfterStaleInterval() async {
        let clock = ManualWiFiClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
        let reader = FakeWiFiSystemReader(result: makeReading(mode: .station, rssi: -50))
        let monitor = makeMonitor(reader: reader, clock: clock)
        var iterator = monitor.updates.makeAsyncIterator()

        monitor.refresh()
        _ = await iterator.next()

        reader.result = nil
        clock.advance(by: 30.001)
        monitor.refresh()

        let status = await iterator.next()
        XCTAssertEqual(status, .placeholder)
    }

    func testStaleReadFailureRecoversAndLaterSuccessRestoresState() async {
        let clock = ManualWiFiClock(now: Date(timeIntervalSinceReferenceDate: 3_000))
        let reader = FakeWiFiSystemReader(result: makeReading(mode: .station, rssi: -50))
        let eventMonitor = FakeWiFiEventMonitor()
        let pathMonitor = FakeWiFiPathMonitor()
        let monitor = makeMonitor(
            reader: reader,
            eventMonitor: eventMonitor,
            pathMonitor: pathMonitor,
            clock: clock
        )
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        let initialStatus = await iterator.next()
        XCTAssertEqual(initialStatus, WiFiStatus(state: .connected, rssi: -50))

        reader.result = nil
        clock.advance(by: 30.001)
        monitor.refresh()
        let staleStatus = await iterator.next()
        XCTAssertEqual(staleStatus, .placeholder)
        XCTAssertEqual(eventMonitor.restartCount, 1)
        XCTAssertEqual(pathMonitor.cancelCount, 1)
        XCTAssertEqual(pathMonitor.startCount, 2)

        monitor.refresh()
        let repeatedFailureStatus = await iterator.next()
        XCTAssertEqual(repeatedFailureStatus, .placeholder)
        XCTAssertEqual(eventMonitor.restartCount, 1)
        XCTAssertEqual(pathMonitor.cancelCount, 1)
        XCTAssertEqual(pathMonitor.startCount, 2)

        clock.advance(by: 30.001)
        monitor.refresh()
        let retryStatus = await iterator.next()
        XCTAssertEqual(retryStatus, .placeholder)
        XCTAssertEqual(eventMonitor.restartCount, 2)
        XCTAssertEqual(pathMonitor.cancelCount, 2)
        XCTAssertEqual(pathMonitor.startCount, 3)

        reader.result = makeReading(mode: .station, rssi: -62)
        monitor.refresh()
        let restoredStatus = await iterator.next()
        XCTAssertEqual(restoredStatus, WiFiStatus(state: .connected, rssi: -62))
        monitor.stop()
    }

    func testCoreWLANModeMapping() {
        XCTAssertEqual(WiFiInterfaceMode(coreWLANMode: .none), .none)
        XCTAssertEqual(WiFiInterfaceMode(coreWLANMode: .station), .station)
        XCTAssertEqual(WiFiInterfaceMode(coreWLANMode: .IBSS), .ibss)
        XCTAssertEqual(WiFiInterfaceMode(coreWLANMode: .hostAP), .hostAP)
    }

    func testCoreWLANEventMonitorRestartRecreatesClientAndRegistersEvents() {
        let firstClient = FakeCoreWLANClient()
        let secondClient = FakeCoreWLANClient()
        var clients = [firstClient, secondClient]
        let eventMonitor = CoreWLANWiFiEventMonitor(
            clientFactory: { clients.removeFirst() }
        )
        let delegate = FakeCWEventDelegate()
        let events: [CWEventType] = [
            .powerDidChange,
            .ssidDidChange,
            .bssidDidChange,
            .linkDidChange
        ]

        eventMonitor.start(delegate: delegate, events: events)
        eventMonitor.restart(delegate: delegate, events: events)

        XCTAssertEqual(firstClient.stopAllCount, 1)
        XCTAssertNil(firstClient.delegate)
        XCTAssertTrue(secondClient.delegate === delegate)
        XCTAssertEqual(secondClient.events, events)
    }

    func testStartRegistersEventsStartsPathMonitorAndRefreshesImmediately() {
        let reader = FakeWiFiSystemReader(result: makeReading(mode: .station, rssi: -55))
        let sharingDetector = FakeInternetSharingDetector(result: false)
        let eventMonitor = FakeWiFiEventMonitor()
        let pathMonitor = FakeWiFiPathMonitor()
        let monitor = makeMonitor(
            reader: reader,
            sharingDetector: sharingDetector,
            eventMonitor: eventMonitor,
            pathMonitor: pathMonitor
        )

        monitor.start()

        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(sharingDetector.callCount, 1)
        XCTAssertEqual(eventMonitor.startCount, 1)
        XCTAssertEqual(
            eventMonitor.events,
            [
                .powerDidChange,
                .ssidDidChange,
                .bssidDidChange,
                .linkDidChange,
                .linkQualityDidChange,
                .modeDidChange
            ]
        )
        XCTAssertTrue(eventMonitor.delegate === monitor)
        XCTAssertEqual(pathMonitor.startCount, 1)
        monitor.stop()
    }

    func testPathUpdateRefreshesWhileRunning() async {
        let reader = FakeWiFiSystemReader(result: makeReading(mode: .station, rssi: -55))
        let pathMonitor = FakeWiFiPathMonitor()
        let monitor = makeMonitor(reader: reader, pathMonitor: pathMonitor)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        let initialStatus = await iterator.next()

        pathMonitor.send(
            WiFiPathSnapshot(satisfied: false, usesWiFi: true, expensive: false)
        )
        let updatedStatus = await iterator.next()

        XCTAssertEqual(initialStatus?.state, .connected)
        XCTAssertEqual(updatedStatus?.state, .noInternet)
        monitor.stop()
    }

    func testConnectionInterruptionRefreshesWithoutRestarting() async {
        let reader = FakeWiFiSystemReader(result: makeReading())
        let eventMonitor = FakeWiFiEventMonitor()
        let pathMonitor = FakeWiFiPathMonitor()
        let monitor = makeMonitor(
            reader: reader,
            eventMonitor: eventMonitor,
            pathMonitor: pathMonitor
        )
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        eventMonitor.delegate?.clientConnectionInterrupted?()
        _ = await iterator.next()

        XCTAssertEqual(reader.readCount, 2)
        XCTAssertEqual(eventMonitor.restartCount, 0)
        XCTAssertEqual(pathMonitor.cancelCount, 0)
        XCTAssertEqual(pathMonitor.startCount, 1)
        monitor.stop()
    }

    func testConnectionInvalidationRestartsAndRefreshes() async {
        let reader = FakeWiFiSystemReader(result: makeReading())
        let eventMonitor = FakeWiFiEventMonitor()
        let pathMonitor = FakeWiFiPathMonitor()
        let monitor = makeMonitor(
            reader: reader,
            eventMonitor: eventMonitor,
            pathMonitor: pathMonitor
        )
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        eventMonitor.delegate?.clientConnectionInvalidated?()
        _ = await iterator.next()

        XCTAssertEqual(reader.readCount, 2)
        XCTAssertEqual(eventMonitor.restartCount, 1)
        XCTAssertEqual(eventMonitor.restartEvents, eventMonitor.events)
        XCTAssertTrue(eventMonitor.delegate === monitor)
        XCTAssertEqual(pathMonitor.cancelCount, 1)
        XCTAssertEqual(pathMonitor.startCount, 2)
        monitor.stop()
    }

    func testLinkQualityCallbacksCoalesceIntoSingleRefresh() async {
        let reader = FakeWiFiSystemReader(result: makeReading(rssi: -50))
        let eventMonitor = FakeWiFiEventMonitor()
        let sleeper = ManualEventSleeper()
        let monitor = makeMonitor(
            reader: reader,
            eventMonitor: eventMonitor,
            refreshDebounceSleep: { duration in
                await sleeper.sleep(duration)
            }
        )
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        for rssi in stride(from: -50, through: -69, by: -1) {
            monitor.linkQualityDidChangeForWiFiInterface(
                withName: "en0",
                rssi: rssi,
                transmitRate: 0
            )
        }

        await sleeper.waitForCallCount(1)
        XCTAssertEqual(reader.readCount, 1)
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(1)
        _ = await iterator.next()

        XCTAssertEqual(reader.readCount, 2)
        monitor.stop()
    }

    func testSSIDAndBSSIDChangesRefresh() async {
        let reader = FakeWiFiSystemReader(result: makeReading())
        let eventMonitor = FakeWiFiEventMonitor()
        let monitor = makeMonitor(reader: reader, eventMonitor: eventMonitor)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        eventMonitor.delegate?.ssidDidChangeForWiFiInterface?(withName: "en0")
        _ = await iterator.next()
        eventMonitor.delegate?.bssidDidChangeForWiFiInterface?(withName: "en0")
        _ = await iterator.next()

        XCTAssertEqual(reader.readCount, 3)
        monitor.stop()
    }

    func testRecoverRestartsMonitoringWithoutFinishingStream() async {
        let reader = FakeWiFiSystemReader(result: makeReading(rssi: -50))
        let eventMonitor = FakeWiFiEventMonitor()
        let pathMonitor = FakeWiFiPathMonitor()
        let monitor = makeMonitor(
            reader: reader,
            eventMonitor: eventMonitor,
            pathMonitor: pathMonitor
        )
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        monitor.recover()

        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(eventMonitor.restartCount, 1)
        XCTAssertEqual(pathMonitor.cancelCount, 1)
        XCTAssertEqual(pathMonitor.startCount, 2)

        reader.result = makeReading(rssi: -70)
        monitor.refresh()
        let recoveredStatus = await iterator.next()
        XCTAssertEqual(recoveredStatus, WiFiStatus(state: .connected, rssi: -70))
        monitor.stop()
    }

    func testRecoverAfterStopDoesNotRestartOrEmit() async {
        let reader = FakeWiFiSystemReader(result: makeReading())
        let eventMonitor = FakeWiFiEventMonitor()
        let pathMonitor = FakeWiFiPathMonitor()
        let monitor = makeMonitor(
            reader: reader,
            eventMonitor: eventMonitor,
            pathMonitor: pathMonitor
        )
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        monitor.stop()

        monitor.recover()

        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(eventMonitor.restartCount, 0)
        XCTAssertEqual(pathMonitor.cancelCount, 1)
        XCTAssertEqual(pathMonitor.startCount, 1)
        let finalStatus = await iterator.next()
        XCTAssertNil(finalStatus)
    }

    func testDeinitWithoutStopTearsDownAndFinishesUpdates() async {
        let eventMonitor = FakeWiFiEventMonitor()
        let pathMonitor = FakeWiFiPathMonitor()
        var monitor: WiFiMonitor? = makeMonitor(
            reader: FakeWiFiSystemReader(result: makeReading()),
            eventMonitor: eventMonitor,
            pathMonitor: pathMonitor
        )
        weak var weakMonitor = monitor
        monitor?.start()
        var iterator = monitor?.updates.makeAsyncIterator()
        _ = await iterator?.next()

        monitor = nil

        XCTAssertNil(weakMonitor)
        XCTAssertEqual(eventMonitor.stopCount, 1)
        XCTAssertEqual(pathMonitor.cancelCount, 1)
        let finalStatus = await iterator?.next()
        XCTAssertNil(finalStatus)
    }

    func testNewerPathSequenceWinsOutOfOrderDelivery() async {
        let reader = FakeWiFiSystemReader(result: makeReading())
        let pathMonitor = FakeWiFiPathMonitor()
        let monitor = makeMonitor(reader: reader, pathMonitor: pathMonitor)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        let older = pathMonitor.makeUpdate(
            WiFiPathSnapshot(satisfied: false, usesWiFi: true, expensive: false)
        )
        let newer = pathMonitor.makeUpdate(
            WiFiPathSnapshot(satisfied: true, usesWiFi: true, expensive: true)
        )
        pathMonitor.deliver(newer)
        pathMonitor.deliver(older)

        let status = await iterator.next()
        XCTAssertEqual(status?.state, .hotspot)
        monitor.stop()
    }

    func testStartIsOneShot() {
        let reader = FakeWiFiSystemReader(result: makeReading())
        let eventMonitor = FakeWiFiEventMonitor()
        let pathMonitor = FakeWiFiPathMonitor()
        let monitor = makeMonitor(
            reader: reader,
            eventMonitor: eventMonitor,
            pathMonitor: pathMonitor
        )

        monitor.start()
        monitor.start()

        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(eventMonitor.startCount, 1)
        XCTAssertEqual(pathMonitor.startCount, 1)
        monitor.stop()
    }

    func testStopIsIdempotentAndFinishesUpdates() async {
        let eventMonitor = FakeWiFiEventMonitor()
        let pathMonitor = FakeWiFiPathMonitor()
        let monitor = makeMonitor(
            reader: FakeWiFiSystemReader(result: makeReading()),
            eventMonitor: eventMonitor,
            pathMonitor: pathMonitor
        )
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        monitor.stop()
        monitor.stop()

        XCTAssertEqual(eventMonitor.stopCount, 1)
        XCTAssertEqual(pathMonitor.cancelCount, 1)
        let finalStatus = await iterator.next()
        XCTAssertNil(finalStatus)
    }

    func testStartAfterStopIsNoOp() {
        let reader = FakeWiFiSystemReader(result: makeReading())
        let eventMonitor = FakeWiFiEventMonitor()
        let pathMonitor = FakeWiFiPathMonitor()
        let monitor = makeMonitor(
            reader: reader,
            eventMonitor: eventMonitor,
            pathMonitor: pathMonitor
        )
        monitor.start()
        monitor.stop()

        monitor.start()

        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(eventMonitor.startCount, 1)
        XCTAssertEqual(pathMonitor.startCount, 1)
    }

    func testStoppedRefreshDoesNotReadOrPublish() async {
        let reader = FakeWiFiSystemReader(result: makeReading())
        let sharingDetector = FakeInternetSharingDetector(result: false)
        let monitor = makeMonitor(reader: reader, sharingDetector: sharingDetector)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        monitor.stop()

        monitor.refresh()

        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(sharingDetector.callCount, 1)
        let finalStatus = await iterator.next()
        XCTAssertNil(finalStatus)
    }

    func testSlowSystemReadLeavesMainActorFreeToUnblockIt() async {
        let started = expectation(description: "background read started")
        let completed = expectation(description: "result returned on main actor")
        let release = DispatchSemaphore(value: 0)
        let reader = CoreWLANStatusReader { _ in
            XCTAssertFalse(Thread.isMainThread)
            started.fulfill()
            // Model synchronous IPC that cannot finish until another task runs.
            // A main-actor implementation times out instead of hanging the suite.
            XCTAssertEqual(release.wait(timeout: .now() + 2), .success)
            return WiFiStatusReading(interface: nil, sharingActive: false)
        }
        reader.read(includeSSID: false) { _ in
            XCTAssertTrue(Thread.isMainThread)
            completed.fulfill()
        }
        await fulfillment(of: [started], timeout: 1)
        release.signal()
        await fulfillment(of: [completed], timeout: 1)
    }

    func testReadAfterAStuckReadStillRuns() async {
        let firstReadStarted = expectation(description: "first read started")
        let secondReadFinished = expectation(description: "second read completed")
        let release = DispatchSemaphore(value: 0)
        let calls = ReadCounter()
        let reader = CoreWLANStatusReader { _ in
            if calls.increment() == 1 {
                firstReadStarted.fulfill()
                // Models a CoreWLAN call that stays blocked; the test frees it
                // only after the follow-up read has already run.
                _ = release.wait(timeout: .now() + 10)
            }
            return WiFiStatusReading(interface: nil, sharingActive: false)
        }

        reader.read(includeSSID: false) { _ in }
        await fulfillment(of: [firstReadStarted], timeout: 5)
        XCTAssertEqual(calls.calls, 1)

        // The first read never returned. This one must not queue behind it.
        reader.read(includeSSID: false) { _ in secondReadFinished.fulfill() }
        await fulfillment(of: [secondReadFinished], timeout: 5)

        XCTAssertEqual(calls.calls, 2)
        release.signal()
    }

    func testAStuckReadIsAbandonedAndTheNextAttemptPublishes() async {
        let reader = DeferredWiFiStatusReader()
        let timeoutSleeper = ManualEventSleeper()
        let monitor = makeMonitor(
            statusReader: reader,
            readTimeoutSleep: { duration in await timeoutSleeper.sleep(duration) }
        )
        var iterator = monitor.updates.makeAsyncIterator()
        monitor.start()
        XCTAssertEqual(reader.includeSSIDRequests.count, 1)

        let retry = expectation(description: "retry read starts")
        reader.onRead = { retry.fulfill() }
        await timeoutSleeper.waitForCallCount(1, timeout: .seconds(5))
        timeoutSleeper.releaseAll()
        await fulfillment(of: [retry], timeout: 5)
        reader.onRead = nil
        XCTAssertEqual(reader.includeSSIDRequests.count, 2, "A stuck read must be retried")

        reader.completeNewest(makeReading(rssi: -52))
        let first = await iterator.next()
        XCTAssertEqual(first?.rssi, -52, "The retry must publish after the stuck read was abandoned")
        monitor.stop()
    }

    func testLateCompletionFromAnAbandonedReadDoesNotReleaseTheNewReadLatch() async {
        let reader = DeferredWiFiStatusReader()
        let timeoutSleeper = ManualEventSleeper()
        let monitor = makeMonitor(
            statusReader: reader,
            readTimeoutSleep: { duration in await timeoutSleeper.sleep(duration) }
        )
        var iterator = monitor.updates.makeAsyncIterator()
        monitor.start()

        let retry = expectation(description: "retry read starts")
        reader.onRead = { retry.fulfill() }
        await timeoutSleeper.waitForCallCount(1, timeout: .seconds(5))
        timeoutSleeper.releaseAll()
        await fulfillment(of: [retry], timeout: 5)
        reader.onRead = nil
        XCTAssertEqual(reader.includeSSIDRequests.count, 2)

        // The abandoned read finally returns while the retry is still outstanding.
        reader.complete(makeReading(rssi: -40))
        monitor.refresh()
        XCTAssertEqual(
            reader.includeSSIDRequests.count, 2,
            "A late completion from an abandoned read must not release the newer read's latch"
        )

        reader.completeNewest(makeReading(rssi: -70))
        let first = await iterator.next()
        XCTAssertEqual(first?.rssi, -70)
        monitor.stop()
    }

    func testSlowReadsCoalesceRepeatedRefreshesIntoOneFollowUp() async {
        let reader = DeferredWiFiStatusReader()
        let monitor = makeMonitor(statusReader: reader)
        var iterator = monitor.updates.makeAsyncIterator()
        monitor.start()
        for _ in 0..<100 { monitor.refresh() }
        XCTAssertEqual(reader.includeSSIDRequests.count, 1)

        reader.complete(makeReading(rssi: -52))
        XCTAssertEqual(reader.includeSSIDRequests.count, 2)
        let first = await iterator.next()
        XCTAssertEqual(first?.rssi, -52)
        reader.complete(makeReading(rssi: -70))
        let second = await iterator.next()
        XCTAssertEqual(second?.rssi, -70)
        XCTAssertEqual(reader.includeSSIDRequests.count, 2)
        monitor.stop()
    }

    func testInvalidationBeforeDebounceCoalescesTheObsoleteReadFollowUp() async {
        let reader = DeferredWiFiStatusReader()
        let sleeper = ManualEventSleeper()
        let monitor = makeMonitor(
            statusReader: reader,
            refreshDebounceSleep: { duration in await sleeper.sleep(duration) }
        )
        monitor.start()
        monitor.clientConnectionInvalidated()
        await sleeper.waitForCallCount(1)

        reader.complete(makeReading(rssi: -40))
        XCTAssertEqual(reader.includeSSIDRequests.count, 1, "The scheduled refresh owns the follow-up")

        let refreshed = expectation(description: "scheduled read starts")
        reader.onRead = { refreshed.fulfill() }
        sleeper.releaseAll()
        await fulfillment(of: [refreshed], timeout: 1)
        reader.onRead = nil
        reader.complete(makeReading(rssi: -65))
        XCTAssertEqual(reader.includeSSIDRequests.count, 2)

        var iterator = monitor.updates.makeAsyncIterator()
        monitor.stop()
        let status = await iterator.next()
        let end = await iterator.next()
        XCTAssertEqual(status?.rssi, -65)
        XCTAssertNil(end, "The invalidated result must not be published")
    }

    func testInvalidationAfterDebounceKeepsOnePendingRefresh() async {
        let reader = DeferredWiFiStatusReader()
        let sleeper = ManualEventSleeper()
        let monitor = makeMonitor(
            statusReader: reader,
            refreshDebounceSleep: { duration in await sleeper.sleep(duration) }
        )
        monitor.start()
        monitor.clientConnectionInvalidated()
        await sleeper.waitForCallCount(1)
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(1)
        // Drain the scheduled main-actor refresh while the system read stays blocked.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(reader.includeSSIDRequests.count, 1)

        reader.complete(makeReading(rssi: -40))
        XCTAssertEqual(reader.includeSSIDRequests.count, 2)
        reader.complete(makeReading(rssi: -65))
        XCTAssertEqual(reader.includeSSIDRequests.count, 2)
        monitor.stop()
    }

    func testStopCancelsScheduledRecoveryWithoutStartingAnotherRead() async {
        let reader = DeferredWiFiStatusReader()
        let sleeper = ManualEventSleeper()
        let monitor = makeMonitor(
            statusReader: reader,
            refreshDebounceSleep: { duration in await sleeper.sleep(duration) }
        )
        monitor.start()
        monitor.refresh()
        monitor.clientConnectionInvalidated()
        await sleeper.waitForCallCount(1)
        monitor.stop()
        reader.complete(makeReading())
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(1)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(reader.includeSSIDRequests.count, 1)
        var iterator = monitor.updates.makeAsyncIterator()
        let end = await iterator.next()
        XCTAssertNil(end)
    }

    func testClosingDetailsDiscardsInFlightSSIDRead() async {
        let reader = DeferredWiFiStatusReader()
        let monitor = makeMonitor(
            statusReader: reader,
            nameAuthorizer: FakeWiFiNameAuthorizer(access: .authorized)
        )
        var iterator = monitor.updates.makeAsyncIterator()
        monitor.start()
        monitor.setDetailsVisible(false)
        reader.complete(makeReading(ssid: "Old network"))
        XCTAssertEqual(reader.includeSSIDRequests, [true, false])
        monitor.stop()
        let obsolete = await iterator.next()
        XCTAssertNil(obsolete)
        reader.complete(makeReading())
        XCTAssertEqual(reader.includeSSIDRequests.count, 2)
    }

    func testPermissionChangeDiscardsInFlightRead() async {
        let reader = DeferredWiFiStatusReader()
        let authorizer = FakeWiFiNameAuthorizer(access: .authorized)
        let monitor = makeMonitor(statusReader: reader, nameAuthorizer: authorizer)
        var iterator = monitor.updates.makeAsyncIterator()
        monitor.start()
        authorizer.setAccess(.denied)
        reader.complete(makeReading(ssid: "Old network"))
        XCTAssertEqual(reader.includeSSIDRequests.count, 2)
        monitor.stop()
        let obsolete = await iterator.next()
        XCTAssertNil(obsolete)
    }

    func testRecoveryDiscardsReadFromBeforeWake() async {
        let reader = DeferredWiFiStatusReader()
        let monitor = makeMonitor(statusReader: reader)
        var iterator = monitor.updates.makeAsyncIterator()
        monitor.start()
        monitor.recover()
        reader.complete(makeReading())
        XCTAssertEqual(reader.includeSSIDRequests.count, 2)
        monitor.stop()
        let obsolete = await iterator.next()
        XCTAssertNil(obsolete)
    }

    func testStopDiscardsSlowReadAndPendingRefresh() async {
        let reader = DeferredWiFiStatusReader()
        let monitor = makeMonitor(statusReader: reader)
        var iterator = monitor.updates.makeAsyncIterator()
        monitor.start()
        monitor.refresh()
        monitor.stop()
        reader.complete(makeReading())
        XCTAssertEqual(reader.includeSSIDRequests.count, 1)
        let obsolete = await iterator.next()
        XCTAssertNil(obsolete)
    }

    func testFailedReadCannotRestoreCachedSSIDAfterAccessOrVisibilityChanges() async {
        for revokePermission in [false, true] {
            let reader = DeferredWiFiStatusReader()
            let authorizer = FakeWiFiNameAuthorizer(access: .authorized)
            let monitor = makeMonitor(statusReader: reader, nameAuthorizer: authorizer)
            var iterator = monitor.updates.makeAsyncIterator()
            monitor.start()
            reader.complete(makeReading(ssid: "Old network"))
            let initial = await iterator.next()
            XCTAssertEqual(initial?.ssid, "Old network")

            if revokePermission {
                authorizer.setAccess(.denied)
            } else {
                monitor.setDetailsVisible(false)
            }
            reader.complete(nil)
            let cached = await iterator.next()
            XCTAssertEqual(cached?.state, .connected)
            XCTAssertNil(cached?.ssid)
            XCTAssertEqual(cached?.nameAccess, revokePermission ? .denied : .authorized)
            monitor.stop()
        }
    }

    func testSlowReadDoesNotRetainMonitor() {
        let reader = DeferredWiFiStatusReader()
        var monitor: WiFiMonitor? = makeMonitor(statusReader: reader)
        weak var weakMonitor = monitor
        monitor?.start()
        monitor = nil
        XCTAssertNil(weakMonitor)
        reader.complete(makeReading())
        XCTAssertEqual(reader.includeSSIDRequests.count, 1)
    }

    private func makeInput(
        powerOn: Bool = true,
        serviceActive: Bool = true,
        mode: WiFiInterfaceMode = .station,
        pathSatisfied: Bool? = true,
        pathUsesWiFi: Bool = true,
        pathExpensive: Bool = false,
        sharingActive: Bool = false
    ) -> WiFiClassificationInput {
        WiFiClassificationInput(
            powerOn: powerOn,
            serviceActive: serviceActive,
            mode: mode,
            pathSatisfied: pathSatisfied,
            pathUsesWiFi: pathUsesWiFi,
            pathExpensive: pathExpensive,
            sharingActive: sharingActive
        )
    }

    func testSystemReaderBandPropagatesAndClearsWithDetailsVisibility() async {
        let reader = FakeWiFiSystemReader(result: makeReading(band: .fiveGHz))
        let monitor = makeMonitor(reader: reader)
        var iterator = monitor.updates.makeAsyncIterator()
        monitor.start()
        let visible = await iterator.next()
        XCTAssertEqual(reader.lastIncludeSSID, true)
        XCTAssertEqual(visible?.band, .fiveGHz)

        monitor.setDetailsVisible(false)
        let hidden = await iterator.next()
        XCTAssertEqual(reader.lastIncludeSSID, false)
        XCTAssertNil(hidden?.band)
        monitor.stop()
    }

    func testFrequencyBandIsOnlyPublishedWhileDetailsAreVisible() async {
        let reader = DeferredWiFiStatusReader()
        let monitor = makeMonitor(statusReader: reader)
        var iterator = monitor.updates.makeAsyncIterator()
        monitor.start()
        reader.complete(makeReading(band: .fiveGHz))
        let visible = await iterator.next()
        XCTAssertEqual(visible?.band, .fiveGHz)

        monitor.setDetailsVisible(false)
        XCTAssertEqual(reader.includeSSIDRequests, [true, false])
        reader.complete(makeReading(band: .sixGHz))
        let hidden = await iterator.next()
        XCTAssertNil(hidden?.band)
        monitor.stop()
    }

    func testUnavailableReadDoesNotReuseCachedFrequencyBand() async {
        let reader = DeferredWiFiStatusReader()
        let monitor = makeMonitor(statusReader: reader)
        var iterator = monitor.updates.makeAsyncIterator()
        monitor.start()
        reader.complete(makeReading(band: .fiveGHz))
        _ = await iterator.next()
        monitor.refresh()
        reader.complete(nil)
        let fallback = await iterator.next()
        XCTAssertEqual(fallback?.state, .connected)
        XCTAssertNil(fallback?.band)
        monitor.stop()
    }

    func testRadioOffClearsResidualFrequencyBand() async {
        let reader = DeferredWiFiStatusReader()
        let monitor = makeMonitor(statusReader: reader)
        var iterator = monitor.updates.makeAsyncIterator()
        monitor.start()
        var reading = makeReading(band: .fiveGHz)
        reading.powerOn = false
        reader.complete(reading)
        let status = await iterator.next()
        XCTAssertEqual(status?.state, .off)
        XCTAssertNil(status?.band)
        monitor.stop()
    }

    private func makeReading(
        mode: WiFiInterfaceMode = .station,
        rssi: Int? = -50,
        ssid: String? = nil,
        band: WiFiFrequencyBand? = nil
    ) -> WiFiSystemReading {
        WiFiSystemReading(
            powerOn: true,
            serviceActive: true,
            mode: mode,
            rssi: rssi,
            ssid: ssid,
            band: band
        )
    }

    private func makeMonitor(
        reader: FakeWiFiSystemReader = FakeWiFiSystemReader(result: nil),
        statusReader: (any WiFiStatusReadingProviding)? = nil,
        sharingDetector: FakeInternetSharingDetector = FakeInternetSharingDetector(result: false),
        nameAuthorizer: FakeWiFiNameAuthorizer = FakeWiFiNameAuthorizer(),
        eventMonitor: FakeWiFiEventMonitor = FakeWiFiEventMonitor(),
        pathMonitor: FakeWiFiPathMonitor = FakeWiFiPathMonitor(),
        staleInterval: TimeInterval = 30,
        initialPath: WiFiPathSnapshot? = nil,
        clock: ManualWiFiClock = ManualWiFiClock(),
        refreshDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        readTimeout: Duration = .seconds(5),
        readTimeoutSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) -> WiFiMonitor {
        WiFiMonitor(
            statusReader: statusReader ?? InlineWiFiStatusReader(reader: reader, sharingDetector: sharingDetector),
            nameAuthorizer: nameAuthorizer,
            eventMonitor: eventMonitor,
            pathMonitor: pathMonitor,
            staleInterval: staleInterval,
            initialPath: initialPath,
            now: { clock.now },
            refreshDebounceSleep: refreshDebounceSleep,
            readTimeout: readTimeout,
            readTimeoutSleep: readTimeoutSleep
        )
    }
}

@MainActor
private final class DeferredWiFiStatusReader: WiFiStatusReadingProviding {
    private(set) var includeSSIDRequests: [Bool] = []
    private var completions: [@MainActor @Sendable (WiFiStatusReading) -> Void] = []
    var onRead: (() -> Void)?

    func read(
        includeSSID: Bool,
        completion: @escaping @MainActor @Sendable (WiFiStatusReading) -> Void
    ) {
        includeSSIDRequests.append(includeSSID)
        completions.append(completion)
        onRead?()
    }

    func complete(_ reading: WiFiSystemReading?) {
        completions.removeFirst()(WiFiStatusReading(interface: reading, sharingActive: false))
    }

    /// Completes the newest outstanding read, leaving older ones pending. Used
    /// when an abandoned read is still outstanding next to its retry.
    func completeNewest(_ reading: WiFiSystemReading?) {
        guard let completion = completions.last else {
            XCTFail("completeNewest() called with no read in flight")
            return
        }
        completion(WiFiStatusReading(interface: reading, sharingActive: false))
    }
}

@MainActor
private final class InlineWiFiStatusReader: WiFiStatusReadingProviding {
    let reader: FakeWiFiSystemReader
    let sharingDetector: FakeInternetSharingDetector

    init(reader: FakeWiFiSystemReader, sharingDetector: FakeInternetSharingDetector) {
        self.reader = reader
        self.sharingDetector = sharingDetector
    }

    func read(
        includeSSID: Bool,
        completion: @escaping @MainActor @Sendable (WiFiStatusReading) -> Void
    ) {
        let reading = reader.read(includeSSID: includeSSID)
        let sharing = reading.map { $0.powerOn && $0.serviceActive } == true
            && sharingDetector.isActive() == true
        completion(WiFiStatusReading(interface: reading, sharingActive: sharing))
    }
}

private final class FakeCoreWLANClient: CWWiFiClient {
    var events: [CWEventType] = []
    var stopAllCount = 0
    weak var storedDelegate: AnyObject?

    override var delegate: AnyObject? {
        get { storedDelegate }
        set { storedDelegate = newValue }
    }

    override func startMonitoringEvent(with event: CWEventType) throws {
        events.append(event)
    }

    override func stopMonitoringAllEvents() throws {
        stopAllCount += 1
    }
}

private final class FakeCWEventDelegate: NSObject, CWEventDelegate {}

private final class FakeWiFiSystemReader: WiFiSystemReadingProviding {
    var result: WiFiSystemReading?
    private(set) var readCount = 0
    private(set) var lastIncludeSSID: Bool?

    init(result: WiFiSystemReading?) {
        self.result = result
    }

    func read() -> WiFiSystemReading? {
        read(includeSSID: true)
    }

    func read(includeSSID: Bool) -> WiFiSystemReading? {
        readCount += 1
        lastIncludeSSID = includeSSID
        guard let result else { return nil }
        return WiFiSystemReading(
            powerOn: result.powerOn,
            serviceActive: result.serviceActive,
            mode: result.mode,
            rssi: result.rssi,
            ssid: includeSSID ? result.ssid : nil,
            band: includeSSID ? result.band : nil
        )
    }
}

private final class FakeInternetSharingDetector: InternetSharingDetecting {
    var result: Bool?
    private(set) var callCount = 0

    init(result: Bool?) {
        self.result = result
    }

    func isActive() -> Bool? {
        callCount += 1
        return result
    }
}

@MainActor
private final class FakeWiFiNameAuthorizer: WiFiNameAuthorizing {
    private(set) var access: WiFiNameAccess
    private(set) var requestCount = 0
    var onAccessChange: (() -> Void)?

    init(access: WiFiNameAccess = .notDetermined) {
        self.access = access
    }

    func requestAccess() {
        requestCount += 1
    }

    func setAccess(_ access: WiFiNameAccess) {
        self.access = access
        onAccessChange?()
    }
}

private final class FakeWiFiEventMonitor: WiFiEventMonitoring {
    private(set) var startCount = 0
    private(set) var restartCount = 0
    private(set) var stopCount = 0
    private(set) var events: [CWEventType] = []
    private(set) var restartEvents: [CWEventType] = []
    weak var delegate: (any CWEventDelegate)?

    func start(delegate: any CWEventDelegate, events: [CWEventType]) {
        startCount += 1
        self.delegate = delegate
        self.events = events
    }

    func restart(delegate: any CWEventDelegate, events: [CWEventType]) {
        restartCount += 1
        self.delegate = delegate
        restartEvents = events
    }

    func stop() {
        stopCount += 1
        delegate = nil
    }
}

private final class FakeWiFiPathMonitor: WiFiPathMonitoring {
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    private var nextSequence: UInt64 = 0
    private var handler: ((WiFiPathUpdate) -> Void)?

    func start(
        queue: DispatchQueue,
        handler: @escaping (WiFiPathUpdate) -> Void
    ) {
        startCount += 1
        self.handler = handler
    }

    func cancel() {
        cancelCount += 1
        handler = nil
    }

    func send(_ snapshot: WiFiPathSnapshot) {
        deliver(makeUpdate(snapshot))
    }

    func makeUpdate(_ snapshot: WiFiPathSnapshot) -> WiFiPathUpdate {
        nextSequence += 1
        return WiFiPathUpdate(sequence: nextSequence, snapshot: snapshot)
    }

    func deliver(_ update: WiFiPathUpdate) {
        handler?(update)
    }
}

private final class ManualWiFiClock {
    private(set) var now: Date

    init(now: Date = Date(timeIntervalSinceReferenceDate: 0)) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}
