import XCTest
@testable import StatusTrioCore

/// Behavioural tests for the VCP `0x10` brightness backend using a mock
/// transport. No IOAVService / I2C hardware is touched, so the real on-device
/// effect stays NOT RUN; these cover resolve → read → write → read-back, fail
/// closed, generation and watchdog.
@MainActor
final class DDCBrightnessCoordinatorTests: XCTestCase {
    func testRebuiltCoordinatorWaitsForOldReadOnSameStableDisplay() async {
        let uid = "REBUILD-\(UUID().uuidString)"
        let oldTransport = FakeBrightnessTransport()
        oldTransport.enqueue(DDCVolumeReply(current: 20, maximum: 100))
        oldTransport.blockNextRead()
        let old = DDCBrightnessCoordinator(transport: oldTransport) { _ in }
        old.select(displayID: uid)
        await waitUntil("old physical read blocked") { oldTransport.hasBlockedRead }
        old.stop()

        let newTransport = FakeBrightnessTransport()
        newTransport.enqueue(DDCVolumeReply(current: 40, maximum: 100))
        var updates: [DDCBrightnessUpdate] = []
        let rebuilt = DDCBrightnessCoordinator(transport: newTransport) { updates.append($0) }
        rebuilt.select(displayID: uid)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(newTransport.resolveCount, 0, "A rebuilt worker must wait before touching the same physical display")
        XCTAssertTrue(updates.isEmpty)
        oldTransport.releaseBlockedRead()
        await waitUntil("rebuilt read after old transport finishes") { updates.last?.scalar == 0.4 }
        XCTAssertEqual(newTransport.resolveCount, 1)
        rebuilt.stop()
    }

    func testBlockedDisplayDoesNotDelayAnotherStableDisplay() async {
        let oldTransport = FakeBrightnessTransport()
        oldTransport.enqueue(DDCVolumeReply(current: 20, maximum: 100))
        oldTransport.blockNextRead()
        let old = DDCBrightnessCoordinator(transport: oldTransport) { _ in }
        old.select(displayID: "BLOCKED-\(UUID().uuidString)")
        await waitUntil("first display blocked") { oldTransport.hasBlockedRead }
        let otherTransport = FakeBrightnessTransport()
        otherTransport.enqueue(DDCVolumeReply(current: 60, maximum: 100))
        var updates: [DDCBrightnessUpdate] = []
        let other = DDCBrightnessCoordinator(transport: otherTransport) { updates.append($0) }
        other.select(displayID: "OTHER-\(UUID().uuidString)")
        await waitUntil("independent display read", timeout: .milliseconds(300)) { updates.last?.scalar == 0.6 }
        oldTransport.releaseBlockedRead()
        await old.waitForWorkerIdle()
        old.stop()
        other.stop()
    }

    func testPendingRebuildIsReplacedAndStopCancelsAdmissionWithoutWaitingForHardware() async {
        let uid = "REPLACE-\(UUID().uuidString)"
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 20, maximum: 100))
        transport.blockNextRead()
        let active = DDCBrightnessCoordinator(transport: transport) { _ in }
        active.select(displayID: uid)
        await waitUntil("old read blocked") { transport.hasBlockedRead }
        active.stop()

        let middleTransport = FakeBrightnessTransport()
        middleTransport.enqueue(DDCVolumeReply(current: 40, maximum: 100))
        var middleUpdates: [DDCBrightnessUpdate] = []
        let middle = DDCBrightnessCoordinator(transport: middleTransport) { middleUpdates.append($0) }
        middle.select(displayID: uid)
        var middleIdle = false
        let middleWait = Task { await middle.waitForWorkerIdle(); middleIdle = true }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(middleIdle, "The idle barrier must include work waiting for admission")

        let newestTransport = FakeBrightnessTransport()
        newestTransport.enqueue(DDCVolumeReply(current: 60, maximum: 100))
        let newest = DDCBrightnessCoordinator(transport: newestTransport) { _ in }
        newest.select(displayID: uid)
        await waitUntil("superseded pending completion") { middleIdle && !middleUpdates.isEmpty }
        XCTAssertEqual(middleUpdates.last?.source, .unavailable(.resolveFailed))
        XCTAssertEqual(middleTransport.resolveCount, 0)
        XCTAssertEqual(newestTransport.resolveCount, 0)
        var newestIdle = false
        let newestWait = Task { await newest.waitForWorkerIdle(); newestIdle = true }
        newest.stop()
        await waitUntil("stopped pending admission cancelled") { newestIdle }
        XCTAssertEqual(newestTransport.resolveCount, 0)

        transport.releaseBlockedRead()
        await active.waitForWorkerIdle()
        await middleWait.value
        await newestWait.value
        middle.stop()
        newest.stop()
    }

    func testContinuousDragWritesBeforeInputStopsAndFlushDoesNotDuplicate() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 20, maximum: 100))
        let coordinator = DDCBrightnessCoordinator(
            transport: transport, debounce: .milliseconds(80), pollInterval: .seconds(600)
        ) { _ in }
        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial read") { transport.readFeatures.count == 1 }
        let first = coordinator.setBrightness(0.3)
        await waitUntil("leading write", timeout: .milliseconds(50)) { transport.writes.count == 1 }
        for value in [0.4, 0.5, 0.6, 0.7, 0.8] {
            _ = coordinator.setBrightness(value)
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertGreaterThanOrEqual(transport.writes.count, 2, "Continuous input must not starve writes")
        coordinator.flushPendingBrightness()
        await waitUntil("final latest write") { transport.writes.last?.value == 80 }
        let count = transport.writes.count
        coordinator.flushPendingBrightness()
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(transport.writes.count, count)
        XCTAssertNotNil(first)
        coordinator.stop()
    }

    func testSlowTransactionCoalescesLatestAndSuppressesOldReadback() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 20, maximum: 100))
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(
            transport: transport, debounce: .milliseconds(5), pollInterval: .seconds(600)
        ) { updates.append($0) }
        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial update") { updates.count == 1 }
        transport.readDelay = 0.3
        let oldCommand = coordinator.setBrightness(0.3)
        coordinator.flushPendingBrightness()
        await waitUntil("first write") { transport.writes.count == 1 }
        // Let the acknowledged write start its slow read-back before newer
        // values arrive, so the coalescing path is exercised deterministically.
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(transport.writes.count, 1)
        var latest: UInt64?
        for value in 40...90 { latest = coordinator.setBrightness(Double(value) / 100) }
        coordinator.flushPendingBrightness()
        XCTAssertEqual(transport.writes.count, 1, "Do not enqueue writes behind an active readback")
        await waitUntil("latest confirmation") { updates.contains { $0.commandID == latest } }
        XCTAssertEqual(transport.writes.map(\.value), [30, 90])
        XCTAssertFalse(updates.contains { $0.commandID == oldCommand }, "Old confirmation must not pull the slider back")
        XCTAssertEqual(updates.last?.scalar, 0.9)
        coordinator.stop()
    }

    func testRepeatedFinalValueStillConfirmsLatestCommandWithoutDuplicateWrite() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 50, maximum: 100))
        transport.enqueue(DDCVolumeReply(current: 50, maximum: 100))
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(
            transport: transport, debounce: .milliseconds(5), pollInterval: .seconds(600)
        ) { updates.append($0) }
        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial update") { updates.count == 1 }
        let firstCommand = coordinator.setBrightness(0.5)
        coordinator.flushPendingBrightness()
        await waitUntil("first confirmation") { updates.contains { $0.commandID == firstCommand } }
        XCTAssertEqual(transport.writes.count, 1)
        let finalCommand = coordinator.setBrightness(0.5)
        coordinator.flushPendingBrightness()
        await waitUntil("same-value final confirmation") { updates.contains { $0.commandID == finalCommand } }
        XCTAssertEqual(updates.last { $0.commandID == finalCommand }?.scalar, 0.5,
                       "BrightnessMonitor drops old reads, so the final command must still publish a confirmation")
        XCTAssertEqual(transport.writes.count, 1, "Same quantized target should not rewrite the display")
        let count = transport.writes.count
        coordinator.flushPendingBrightness()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(transport.writes.count, count)
        coordinator.stop()
    }

    func testReturnToEarlierValueCannotReuseConfirmationAfterInterveningWrite() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 10, maximum: 100))
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(transport: transport, debounce: .milliseconds(10)) {
            updates.append($0)
        }
        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial read") { updates.count == 1 }
        let confirmed = coordinator.setBrightness(0.2)
        await waitUntil("confirmed twenty") { updates.contains { $0.commandID == confirmed && $0.scalar == 0.2 } }
        transport.blockNextRead()
        _ = coordinator.setBrightness(0.8)
        coordinator.flushPendingBrightness()
        await waitUntil("eighty readback blocked") { transport.hasBlockedRead }
        let final = coordinator.setBrightness(0.2)
        coordinator.flushPendingBrightness()
        transport.releaseBlockedRead()
        await waitUntil("twenty confirmed again") { updates.contains { $0.commandID == final } }
        XCTAssertEqual(transport.writeCalls.map(\.value), [20, 80, 20])
        XCTAssertEqual(updates.last?.scalar, 0.2)
        coordinator.stop()
    }

    func testSameQuantizedValueDuringReadbackConfirmsFinalCommandOnce() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 10, maximum: 100))
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(transport: transport) { updates.append($0) }
        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial update") { updates.count == 1 }
        transport.blockNextRead()
        _ = coordinator.setBrightness(0.501)
        coordinator.flushPendingBrightness()
        await waitUntil("blocked confirmation") { transport.hasBlockedRead }
        let final = coordinator.setBrightness(0.504)
        coordinator.flushPendingBrightness()
        transport.releaseBlockedRead()
        await waitUntil("latest quantized confirmation") { updates.contains { $0.commandID == final } }
        XCTAssertEqual(transport.writeCalls.map(\.value), [50])
        XCTAssertEqual(updates.last?.scalar, 0.5)
        coordinator.stop()
    }

    func testLifecycleChangeDropsPendingWritesAndStaleConfirmation() async {
        for change in ["stop", "sleep", "disconnect", "topology"] {
            let transport = FakeBrightnessTransport()
            transport.enqueue(DDCVolumeReply(current: 10, maximum: 100))
            var updates: [DDCBrightnessUpdate] = []
            let coordinator = DDCBrightnessCoordinator(transport: transport) { updates.append($0) }
            coordinator.select(displayID: "DISPLAY-A")
            await waitUntil("initial read for \(change)") { updates.count == 1 }
            transport.blockNextRead()
            let old = coordinator.setBrightness(0.3)
            coordinator.flushPendingBrightness()
            await waitUntil("blocked read for \(change)") { transport.hasBlockedRead }
            for value in 40...90 { _ = coordinator.setBrightness(Double(value) / 100) }
            coordinator.flushPendingBrightness()
            switch change {
            case "stop": coordinator.stop()
            case "sleep": coordinator.setDisplayAsleep(true)
            case "disconnect": coordinator.select(displayID: "")
            default: coordinator.topologyChanged()
            }
            transport.releaseBlockedRead()
            await coordinator.waitForWorkerIdle()
            try? await Task.sleep(for: .milliseconds(180))
            XCTAssertEqual(transport.writeCalls.map(\.value), [30], change)
            XCTAssertFalse(updates.contains { $0.commandID == old }, change)
            coordinator.stop()
        }
    }

    func testStopCancelsIdlePolling() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 10, maximum: 100))
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(
            transport: transport, debounce: .milliseconds(10), pollInterval: .milliseconds(10)
        ) { updates.append($0) }
        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial read") { updates.count == 1 }
        let command = coordinator.setBrightness(0.7)
        coordinator.flushPendingBrightness()
        await waitUntil("confirmed write") { updates.contains { $0.commandID == command } }
        coordinator.stop()
        let reads = transport.readFeatures.count
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(transport.readFeatures.count, reads, "A stopped coordinator must not keep polling")
    }

    func testSameValueDoesNotTrustCacheWhenDisplayDriftedExternally() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 10, maximum: 100))
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(transport: transport, debounce: .milliseconds(10)) {
            updates.append($0)
        }
        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial read") { updates.count == 1 }
        let first = coordinator.setBrightness(0.5)
        coordinator.flushPendingBrightness()
        await waitUntil("first confirm") { updates.contains { $0.commandID == first && $0.scalar == 0.5 } }
        // Something else moved the display to 70 before the user repeats 0.5.
        transport.enqueue(DDCVolumeReply(current: 70, maximum: 100))
        let second = coordinator.setBrightness(0.5)
        coordinator.flushPendingBrightness()
        await waitUntil("drift rejected") { updates.contains { $0.commandID == second } }
        XCTAssertNil(updates.last?.scalar)
        XCTAssertEqual(updates.last?.source, .unavailable(.writeNotConfirmed),
                       "A fresh mismatch must not be reported as success from the cached value")
        XCTAssertEqual(transport.writeCalls.map(\.value), [50])
        coordinator.stop()
    }

    func testCachedConfirmationHasWatchdogAndKeepsBlockedTransactionBounded() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 10, maximum: 100))
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(
            transport: transport, debounce: .milliseconds(10), readWatchdog: .milliseconds(30)
        ) { updates.append($0) }
        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial read") { updates.count == 1 }
        let first = coordinator.setBrightness(0.5)
        coordinator.flushPendingBrightness()
        await waitUntil("first confirmation") { updates.contains { $0.commandID == first } }
        transport.blockNextRead()
        let same = coordinator.setBrightness(0.504)
        coordinator.flushPendingBrightness()
        await waitUntil("same-value read blocked") { transport.hasBlockedRead }
        await waitUntil("cached confirmation timeout") {
            updates.contains { $0.commandID == same && $0.source == .unavailable(.timeout) }
        }
        let latest = coordinator.setBrightness(0.9)
        for _ in 0..<50 { coordinator.flushPendingBrightness(); coordinator.refresh() }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(transport.writeCalls.map(\.value), [50], "A watchdog must not release physical transport ownership")
        transport.releaseBlockedRead()
        await waitUntil("latest after blocked confirmation") { updates.contains { $0.commandID == latest && $0.scalar == 0.9 } }
        XCTAssertEqual(transport.writeCalls.map(\.value), [50, 90])
        coordinator.stop()
    }

    func testReleaseDuringSlowReadBypassesRemainingPacing() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 10, maximum: 100))
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(transport: transport, debounce: .seconds(5)) { updates.append($0) }
        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial read") { updates.count == 1 }
        transport.blockNextRead()
        _ = coordinator.setBrightness(0.3)
        await waitUntil("blocked leading readback") { transport.hasBlockedRead }
        _ = coordinator.setBrightness(0.8)
        coordinator.flushPendingBrightness()
        transport.releaseBlockedRead()
        await waitUntil("released final value", timeout: .milliseconds(300)) { transport.writeCalls.last?.value == 80 }
        XCTAssertEqual(transport.writeCalls.map(\.value), [30, 80])
        coordinator.stop()
    }

    func testGenerationChangeDuringWriteRangeReadCancelsOldHardwareWrite() async {
        for change in ["stop", "sleep", "topology", "selection"] {
            let transport = FakeBrightnessTransport()
            transport.enqueue(DDCVolumeReply(current: 10, maximum: 100))
            var updates: [DDCBrightnessUpdate] = []
            let coordinator = DDCBrightnessCoordinator(transport: transport) { updates.append($0) }
            coordinator.select(displayID: "DISPLAY-A")
            await waitUntil("initial read for \(change)") { updates.count == 1 }
            transport.failNextReads(1, with: .replyReadFailed)
            transport.blockRead(attempt: 3)
            transport.enqueue(DDCVolumeReply(current: 20, maximum: 100))
            coordinator.refresh() // Attempt 2 fails, dropping the worker's cached range.
            _ = coordinator.setBrightness(0.7)
            coordinator.flushPendingBrightness()
            await waitUntil("write range read blocked for \(change)") { transport.hasBlockedRead }
            transport.enqueue(DDCVolumeReply(current: 40, maximum: 100))
            switch change {
            case "stop": coordinator.stop()
            case "sleep": coordinator.setDisplayAsleep(true)
            case "topology": coordinator.topologyChanged()
            default: coordinator.select(displayID: "DISPLAY-B")
            }
            transport.releaseBlockedRead()
            await coordinator.waitForWorkerIdle()
            try? await Task.sleep(for: .milliseconds(30))
            XCTAssertTrue(transport.writeCalls.isEmpty, "Cancelled generation must not program hardware after range read: \(change)")
            if change != "stop" {
                if change == "sleep" { coordinator.setDisplayAsleep(false) }
                let current = coordinator.setBrightness(0.8)
                coordinator.flushPendingBrightness()
                await waitUntil("new generation remains live for \(change)") {
                    updates.contains { $0.commandID == current && $0.scalar == 0.8 }
                }
                XCTAssertEqual(transport.writeCalls.map(\.value), [80], change)
            }
            coordinator.stop()
        }
    }

    func testSelectionReadsBrightnessAndEmitsScalar() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 40, maximum: 100))
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(transport: transport) { updates.append($0) }

        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial brightness read") { updates.contains { $0.scalar == 0.4 } }

        let update = try? XCTUnwrap(updates.last)
        XCTAssertEqual(update?.displayID, "DISPLAY-A")
        XCTAssertEqual(update?.source, .directDDC)
        XCTAssertEqual(update?.canAdjust, true)
        XCTAssertEqual(update?.generation, coordinator.generation)
        XCTAssertEqual(transport.readFeatures, [DDCPacket.brightnessVCP])
        coordinator.stop()
    }

    func testWriteReadsBackAndConfirmsOnExactMatch() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 30, maximum: 100)) // initial read
        transport.enqueue(DDCVolumeReply(current: 70, maximum: 100)) // read-back
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(
            transport: transport,
            debounce: .milliseconds(10),
            pollInterval: .seconds(600)
        ) { updates.append($0) }

        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial read") { updates.contains { $0.scalar == 0.3 } }

        let commandID = coordinator.setBrightness(0.7)
        await waitUntil("confirmed write update") {
            updates.contains { $0.commandID == commandID && $0.scalar == 0.7 }
        }

        XCTAssertEqual(transport.writeCalls.map(\.value), [70])
        XCTAssertEqual(transport.writeCalls.map(\.feature), [DDCPacket.brightnessVCP])
        XCTAssertEqual(updates.last?.source, .directDDC, "A verified read-back is a success")
        coordinator.stop()
    }

    func testWriteReadBackMismatchFailsClosed() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 30, maximum: 100)) // initial read
        transport.enqueue(DDCVolumeReply(current: 30, maximum: 100)) // read-back did NOT move
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(
            transport: transport,
            debounce: .milliseconds(10),
            pollInterval: .seconds(600)
        ) { updates.append($0) }

        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial read") { updates.contains { $0.scalar == 0.3 } }

        let commandID = coordinator.setBrightness(0.7)
        await waitUntil("mismatched read-back update") {
            updates.contains { $0.commandID == commandID }
        }

        let update = try? XCTUnwrap(updates.last { $0.commandID == commandID })
        XCTAssertNil(update?.scalar, "A failed confirmation must not publish an optimistic value")
        XCTAssertEqual(update?.source, .unavailable(.writeNotConfirmed))
        XCTAssertEqual(update?.canAdjust, false,
                       "An unconfirmed write must not keep the slider enabled while the error text is hidden")
        coordinator.stop()
    }

    func testReadFailureMapsRefusedVCPToUnsupportedReason() async {
        let transport = FakeBrightnessTransport()
        transport.failNextReads(1, with: .replyRejected(.vcpRefused))
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(
            transport: transport,
            pollInterval: .seconds(600)
        ) { updates.append($0) }

        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("unavailable update") { updates.contains { $0.source == .unavailable(.unsupportedVCP) } }

        XCTAssertEqual(updates.last?.scalar, nil)
        XCTAssertEqual(updates.last?.canAdjust, false)
        coordinator.stop()
    }

    func testResolveFailureIsFailClosedWithNoWrite() async {
        let transport = FakeBrightnessTransport()
        transport.resolveSucceeds = false
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(
            transport: transport,
            debounce: .milliseconds(10),
            pollInterval: .seconds(600)
        ) { updates.append($0) }

        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("resolve failure update") { updates.contains { $0.source == .unavailable(.resolveFailed) } }

        coordinator.setBrightness(0.5)
        coordinator.flushPendingBrightness()
        await coordinator.waitForWorkerIdle()
        XCTAssertTrue(transport.writeCalls.isEmpty, "An unresolved display must never be written")
        coordinator.stop()
    }

    func testStalledReadWatchdogEmitsTimeout() async {
        let transport = FakeBrightnessTransport()
        let box = TimeoutBox()
        let coordinator = DDCBrightnessCoordinator(
            transport: transport,
            readWatchdog: .milliseconds(40),
            pollInterval: .seconds(600),
            onWatchdogTimeout: { _, _ in box.fired = true }
        ) { updates in box.updates.append(updates) }

        transport.blockNextRead()
        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("read enters blocking state") { transport.hasBlockedRead }
        await waitUntil("watchdog timeout update") {
            box.updates.contains { $0.source == .unavailable(.timeout) }
        }
        XCTAssertTrue(box.fired, "Watchdog handler must fire once")

        transport.releaseBlockedRead()
        await coordinator.waitForWorkerIdle()
        coordinator.stop()
    }

    func testTopologyChangeBumpsGenerationAndRepublishes() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 20, maximum: 100))
        transport.enqueue(DDCVolumeReply(current: 60, maximum: 100))
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(
            transport: transport,
            pollInterval: .seconds(600)
        ) { updates.append($0) }

        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial read") { updates.contains { $0.scalar == 0.2 } }
        let firstGeneration = coordinator.generation

        coordinator.topologyChanged()
        await waitUntil("post-topology read") { updates.contains { $0.scalar == 0.6 } }

        XCTAssertGreaterThan(coordinator.generation, firstGeneration)
        XCTAssertEqual(updates.last?.generation, coordinator.generation)
        coordinator.stop()
    }

    // MARK: - Helpers

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for \(description)", file: file, line: line)
    }
}

@MainActor
private final class TimeoutBox {
    var fired = false
    var updates: [DDCBrightnessUpdate] = []
}

/// Mock DDC transport. It only models resolve / read / write; there is no I2C.
private final class FakeBrightnessTransport: DDCFeatureTransport, @unchecked Sendable {
    private struct WriteCall {
        let value: UInt16
        let feature: UInt8
    }

    private let lock = NSLock()
    private var replyQueue: [DDCVolumeReply] = []
    private var pendingReadFailures: [DDCReadFailure] = []
    private var storedReadFeatures: [UInt8] = []
    private var storedWriteCalls: [WriteCall] = []
    private var storedResolveCount = 0
    private var storedResolveSucceeds = true
    private var storedWriteAcknowledged = true
    private var blockNextReadFlag = false
    private var blockedReadAttempt: Int?
    private var readAttempt = 0
    private var blockedReadEntered = false
    private var storedReadDelay: TimeInterval = 0
    private let blockedReadSemaphore = DispatchSemaphore(value: 0)

    var resolveSucceeds: Bool {
        get { lock.withLock { storedResolveSucceeds } }
        set { lock.withLock { storedResolveSucceeds = newValue } }
    }
    var readFeatures: [UInt8] { lock.withLock { storedReadFeatures } }
    var writeCalls: [(value: UInt16, feature: UInt8)] {
        lock.withLock { storedWriteCalls.map { ($0.value, $0.feature) } }
    }
    var writes: [(value: UInt16, feature: UInt8)] { writeCalls }
    var readDelay: TimeInterval {
        get { lock.withLock { storedReadDelay } }
        set { lock.withLock { storedReadDelay = newValue } }
    }
    var resolveCount: Int { lock.withLock { storedResolveCount } }
    var hasBlockedRead: Bool { lock.withLock { blockedReadEntered } }

    func enqueue(_ reply: DDCVolumeReply) {
        lock.withLock { replyQueue.append(reply) }
    }

    func failNextReads(_ count: Int, with failure: DDCReadFailure) {
        lock.withLock {
            for _ in 0..<count { pendingReadFailures.append(failure) }
        }
    }

    func blockNextRead() {
        lock.withLock { blockNextReadFlag = true }
    }

    func blockRead(attempt: Int) {
        lock.withLock { blockedReadAttempt = attempt }
    }

    func releaseBlockedRead() {
        blockedReadSemaphore.signal()
    }

    // MARK: DDCVolumeTransport

    func resolve(uid: String) -> DDCDisplayTarget? {
        lock.withLock { storedResolveCount += 1; return storedResolveSucceeds ? DDCDisplayTarget(uid: uid, service: nil) : nil }
    }

    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult {
        read(target, feature: DDCPacket.volumeVCP)
    }

    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool {
        write(target, value: value, feature: DDCPacket.volumeVCP)
    }

    // MARK: DDCFeatureTransport

    func read(_ target: DDCDisplayTarget, feature: UInt8) -> DDCVolumeReadResult {
        let shouldBlock: Bool = lock.withLock {
            readAttempt += 1
            let flag = blockNextReadFlag || blockedReadAttempt == readAttempt
            if flag { blockNextReadFlag = false; blockedReadEntered = true }
            return flag
        }
        if shouldBlock { blockedReadSemaphore.wait() }
        let delay = lock.withLock { storedReadDelay }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }

        return lock.withLock {
            storedReadFeatures.append(feature)
            if !pendingReadFailures.isEmpty {
                return .failure(pendingReadFailures.removeFirst())
            }
            guard !replyQueue.isEmpty else {
                // Model a display echoing the last written value so read-backs
                // confirm without hand-enqueueing one reply per drag step.
                if let last = storedWriteCalls.last {
                    return .reply(DDCVolumeReply(current: last.value, maximum: 100))
                }
                return .failure(.replyReadFailed)
            }
            return .reply(replyQueue.removeFirst())
        }
    }

    func write(_ target: DDCDisplayTarget, value: UInt16, feature: UInt8) -> Bool {
        lock.withLock {
            storedWriteCalls.append(WriteCall(value: value, feature: feature))
            return storedWriteAcknowledged
        }
    }
}
