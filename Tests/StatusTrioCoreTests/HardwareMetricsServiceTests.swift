import XCTest
import Combine
@testable import StatusTrioCore

@MainActor
final class HardwareMetricsServiceTests: XCTestCase {
    /// Controllable clock for cadence assertions.
    private final class Clock {
        var date: Date = Date(timeIntervalSince1970: 1_000)
        func advance(_ interval: TimeInterval) { date = date.addingTimeInterval(interval) }
    }

    /// Thread-safe recorder for reads and their continuations, so the @Sendable
    /// reader closure can hand control back to the test without capturing a
    /// mutable local.
    private final class Recorder: @unchecked Sendable {
        private let queue = DispatchQueue(label: "HardwareMetricsServiceTests.Recorder")
        private var storedCalls: [Set<HardwareMetricID>] = []
        private var storedContinuations: [CheckedContinuation<HardwareMetricsSnapshot, Never>] = []

        var calls: [Set<HardwareMetricID>] {
            queue.sync { storedCalls }
        }

        var continuations: [CheckedContinuation<HardwareMetricsSnapshot, Never>] {
            queue.sync { storedContinuations }
        }

        /// Reader that records the request and parks until the test resumes it.
        func waitingReader() -> HardwareMetricsService.Reader {
            { ids, _ in
                await withCheckedContinuation { continuation in
                    self.queue.sync {
                        self.storedCalls.append(ids)
                        self.storedContinuations.append(continuation)
                    }
                }
            }
        }

        /// Reader that records the request and answers immediately.
        func countingReader(usage: Double) -> HardwareMetricsService.Reader {
            { ids, date in
                self.queue.sync { self.storedCalls.append(ids) }
                return HardwareMetricsSnapshot(samples: [
                    .cpuUsage: HardwareMetricSample(value: usage, unit: .percent,
                                                    sampledAt: date, source: .mach,
                                                    availability: .measured)
                ])
            }
        }
    }

    private func snapshot(usage: Double, at date: Date) -> HardwareMetricsSnapshot {
        .init(samples: [.cpuUsage: .init(value: usage, unit: .percent, sampledAt: date,
                                        source: .mach, availability: .measured)])
    }

    /// Wait until the service has no read outstanding and the reader ran.
    private func awaitSettled(_ service: HardwareMetricsService, _ recorder: Recorder) async {
        for _ in 0..<200 {
            await Task.yield()
            if !service.isAwaitingReadForTesting, !recorder.calls.isEmpty { return }
        }
    }

    private func awaitSettledUntil(_ service: HardwareMetricsService,
                                   _ condition: @escaping () -> Bool) async {
        for _ in 0..<200 {
            await Task.yield()
            if !service.isAwaitingReadForTesting, condition() { return }
        }
    }

    /// Wait until the reader has been entered `expected` times and no read is
    /// outstanding (for immediate readers).
    private func awaitSettled(_ service: HardwareMetricsService,
                              recorderCalls: @escaping () -> Int,
                              expected: Int) async {
        for _ in 0..<200 {
            await Task.yield()
            if !service.isAwaitingReadForTesting, recorderCalls() >= expected { return }
        }
    }

    /// Wait until a parked reader has been entered `count` times.
    private func awaitReadingStarted(_ recorder: Recorder, count: Int = 1) async {
        for _ in 0..<200 {
            await Task.yield()
            if recorder.calls.count >= count { return }
        }
    }

    private func drain(_ count: Int = 40) async {
        for _ in 0..<count { await Task.yield() }
    }

    func testBackgroundSamplesPopulateHistoryAndSurvivePanelHandoff() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false, now: { clock.date },
                                             reader: recorder.countingReader(usage: 42))
        service.begin(.background, metrics: [.cpuUsage])
        await awaitSettled(service, recorderCalls: { recorder.calls.count }, expected: 1)
        XCTAssertGreaterThan(service.observable.historyRowsForDetail.count, 0,
                             "background sampling must be recorded into session history")

        // Opening the panel ends the background demand first; history must survive.
        service.end(.background)
        XCTAssertGreaterThan(service.observable.historyRowsForDetail.count, 0)
        service.begin(.panel, metrics: [.cpuUsage])
        await awaitSettled(service, recorderCalls: { recorder.calls.count }, expected: 2)
        XCTAssertGreaterThan(service.observable.historyRowsForDetail.count, 0)
        service.stopAll()
    }

    func testRingFrequencyDoesNotStarveTemperatureDemand() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false, now: { clock.date },
                                             reader: recorder.countingReader(usage: 20))
        service.wantsRingCPUFrequency = true
        service.begin(.menuBarArc, metrics: [.cpuUsage, .cpuTemperature])
        service.begin(.panel, metrics: [.cpuUsage, .cpuTemperature])
        await awaitSettled(service, recorderCalls: { recorder.calls.count }, expected: 1)
        XCTAssertTrue(recorder.calls.contains { $0.contains(.cpuTemperature) },
                      "a menu-bar temperature arc must keep requesting the temperature")
        service.stopAll()
    }

    func testTemperatureMonitoringOffRemovesTemperatureFromReads() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false, now: { clock.date },
                                             reader: recorder.countingReader(usage: 10))
        service.temperatureMonitoringEnabled = false
        service.begin(.panel, metrics: [.cpuUsage, .cpuTemperature, .gpuTemperature])
        await awaitSettled(service, recorderCalls: { recorder.calls.count }, expected: 1)
        let first = recorder.calls.first ?? []
        XCTAssertTrue(first.contains(.cpuUsage))
        XCTAssertFalse(first.contains(.cpuTemperature))
        XCTAssertFalse(first.contains(.gpuTemperature))

        service.temperatureMonitoringEnabled = true
        service.forceRefresh()
        await awaitSettled(service, recorderCalls: { recorder.calls.count }, expected: 2)
        let second = recorder.calls.last ?? []
        XCTAssertTrue(second.contains(.cpuTemperature))
        XCTAssertTrue(second.contains(.gpuTemperature))
        service.stopAll()
    }

    func testTickIntervalFollowsFastestDemandedMetric() async {
        let clock = Clock()
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: { _, _ in .empty })
        service.begin(.panel, metrics: [.cpuTemperature])
        XCTAssertEqual(service.currentTickIntervalForTesting, 4,
                       "sensors alone need only wake every 4s")
        service.begin(.menuBarArc, metrics: [.cpuUsage])
        XCTAssertEqual(service.currentTickIntervalForTesting, 2,
                       "a 2s usage consumer raises the loop frequency")
        service.end(.menuBarArc)
        XCTAssertEqual(service.currentTickIntervalForTesting, 4)
        service.stopAll()
    }

    func testNoDemandDoesNotReadAndRepeatedBeginIsDeduplicated() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: recorder.countingReader(usage: 25))
        service.refreshIfNeeded(forceFamilies: [])
        await drain()
        XCTAssertEqual(recorder.calls.count, 0)
        XCTAssertFalse(service.isRunning)

        service.begin(.panel, metrics: [.cpuUsage])
        await awaitSettled(service, recorder)
        XCTAssertEqual(recorder.calls.count, 1)

        service.begin(.panel, metrics: [.cpuUsage])
        await drain()
        XCTAssertEqual(recorder.calls.count, 1)

        service.end(.panel)
        XCTAssertFalse(service.isRunning)
        // The last fresh frame is kept as a cache (not blanked) so reopening is
        // instant; with the clock unchanged it is still within freshness.
        XCTAssertEqual(service.observable.snapshot.cpuUsage.value, 25)
        service.refreshIfNeeded(forceFamilies: [])
        await drain()
        XCTAssertEqual(recorder.calls.count, 1)
    }

    func testMetricMaskOnlyReadsDemandedFamiliesAndSlowSensorCadence() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: recorder.countingReader(usage: 10))
        service.begin(.panel, metrics: [.cpuUsage, .cpuTemperature, .fanRPM(index: 0)])
        await awaitSettled(service, recorder)
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(recorder.calls[0], [.cpuUsage, .cpuTemperature, .fanRPM(index: 0)])

        clock.advance(2)
        service.refreshIfNeeded(forceFamilies: [])
        await awaitSettled(service, recorder)
        XCTAssertEqual(recorder.calls.count, 2)
        XCTAssertEqual(recorder.calls[1], [.cpuUsage])

        clock.advance(2)
        service.refreshIfNeeded(forceFamilies: [])
        await awaitSettled(service, recorder)
        XCTAssertEqual(recorder.calls.count, 3)
        XCTAssertTrue(recorder.calls[2].contains(.cpuTemperature))
        XCTAssertTrue(recorder.calls[2].contains(.fanRPM(index: 0)))
        service.stopAll()
    }

    func testUsageOnlyDemandNeverReadsSensors() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: recorder.countingReader(usage: 5))
        service.begin(.panel, metrics: [.cpuUsage])
        await awaitSettled(service, recorder)
        clock.advance(10)
        service.refreshIfNeeded(forceFamilies: [])
        await awaitSettled(service, recorder)
        XCTAssertEqual(recorder.calls.count, 2)
        XCTAssertTrue(recorder.calls.allSatisfy { $0 == [.cpuUsage] })
        service.stopAll()
    }

    func testSleepDiscardsInFlightAndWakeRefreshes() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: recorder.waitingReader())
        service.begin(.panel, metrics: [.cpuUsage])
        await awaitReadingStarted(recorder)
        XCTAssertEqual(recorder.calls.count, 1)

        clock.advance(30)
        service.sleep()
        service.wake()
        await drain()
        XCTAssertEqual(recorder.calls.count, 1,
                       "wake must wait for the old physical read instead of overlapping")

        recorder.continuations[0].resume(returning: snapshot(usage: 99, at: clock.date))
        await awaitReadingStarted(recorder, count: 2)
        XCTAssertEqual(recorder.calls.count, 2)
        XCTAssertNil(service.observable.snapshot.cpuUsage.value,
                     "no value was ever published before sleep, and the late read is discarded")

        recorder.continuations[1].resume(returning: snapshot(usage: 70, at: clock.date))
        await drain()
        XCTAssertEqual(service.observable.snapshot.cpuUsage.value, 70)
        service.stopAll()
    }

    func testReopenShowsCachedValueUntilFreshReadLands() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: recorder.waitingReader())
        service.begin(.panel, metrics: [.cpuUsage])
        await awaitReadingStarted(recorder)
        recorder.continuations[0].resume(returning: snapshot(usage: 42, at: clock.date))
        await drain()
        XCTAssertEqual(service.observable.snapshot.cpuUsage.value, 42)

        service.end(.panel)
        clock.advance(30)               // panel closed for a while
        service.begin(.panel, metrics: [.cpuUsage])
        await awaitReadingStarted(recorder, count: 2)
        XCTAssertEqual(service.observable.snapshot.cpuUsage.value, 42,
                       "reopening shows the cached last reading, not a blank dash")
        XCTAssertEqual(service.observable.snapshot.cpuUsage.availability, .stale)

        recorder.continuations[1].resume(returning: snapshot(usage: 55, at: clock.date))
        await drain()
        XCTAssertEqual(service.observable.snapshot.cpuUsage.value, 55)
        XCTAssertEqual(service.observable.snapshot.cpuUsage.availability, .measured)
        service.stopAll()
    }

    func testEndingDemandDiscardsLateResultAndClears() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: recorder.waitingReader())
        service.begin(.panel, metrics: [.cpuUsage])
        await awaitReadingStarted(recorder)
        service.end(.panel)
        guard let continuation = recorder.continuations.first else {
            return XCTFail("expected an in-flight read")
        }
        continuation.resume(returning: snapshot(usage: 99, at: clock.date))
        await drain()
        XCTAssertNil(service.observable.snapshot.cpuUsage.value)
        XCTAssertFalse(service.isRunning)
    }

    func testWakeWithoutConsumersDoesNotRead() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: recorder.countingReader(usage: 1))
        service.wake()
        await drain()
        XCTAssertEqual(recorder.calls.count, 0)
        XCTAssertFalse(service.isRunning)
    }

    /// A usage-only refresh must not wipe the slower sensor samples.
    private final class ScriptedReader: @unchecked Sendable {
        private let queue = DispatchQueue(label: "HardwareMetricsServiceTests.Scripted")
        private var index = 0
        private var storedCalls = 0
        private let frames: [HardwareMetricsSnapshot]
        init(_ frames: [HardwareMetricsSnapshot]) { self.frames = frames }
        var calls: Int { queue.sync { storedCalls } }
        func reader() -> HardwareMetricsService.Reader {
            { _, _ in
                self.queue.sync {
                    defer {
                        self.index += 1
                        self.storedCalls += 1
                    }
                    return self.frames[min(self.index, self.frames.count - 1)]
                }
            }
        }
    }

    func testUsageOnlyRefreshKeepsSlowerSensorSamples() async {
        var first = HardwareMetricsSnapshot.empty
        let clock = Clock()
        first.samples[.cpuUsage] = .init(value: 10, unit: .percent, sampledAt: clock.date,
                                         source: .mach, availability: .measured)
        first.samples[.cpuTemperature] = .init(value: 62, unit: .celsius, sampledAt: clock.date,
                                               source: .smc, availability: .measured)
        first.fanCount = 1
        first.samples[.fanRPM(index: 0)] = .init(value: 2_450, unit: .rpm, sampledAt: clock.date,
                                                 source: .smc, availability: .measured,
                                                 metadata: .init(maximum: 5_000))
        var usageOnly = HardwareMetricsSnapshot.empty
        usageOnly.samples[.cpuUsage] = .init(value: 20, unit: .percent, sampledAt: clock.date,
                                             source: .mach, availability: .measured)
        let scripted = ScriptedReader([first, usageOnly])
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: scripted.reader())
        service.begin(.panel, metrics: [.cpuUsage, .cpuTemperature, .fanRPM(index: 0)])
        await awaitSettled(service, recorderCalls: { scripted.calls }, expected: 1)
        XCTAssertEqual(service.observable.snapshot.cpuTemperature.value, 62)

        clock.advance(2)
        service.refreshIfNeeded(forceFamilies: [])
        await awaitSettled(service, recorderCalls: { scripted.calls }, expected: 2)
        XCTAssertEqual(service.observable.snapshot.cpuUsage.value, 20)
        XCTAssertEqual(service.observable.snapshot.cpuTemperature.value, 62,
                       "usage-only refresh must not drop the sensor frame")
        XCTAssertEqual(service.observable.snapshot.fanSummarySample.value, 2_450)
        service.stopAll()
    }

    func testSleepKeepsCachedSnapshot() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: recorder.countingReader(usage: 42))
        service.begin(.panel, metrics: [.cpuUsage])
        await awaitSettled(service, recorderCalls: { recorder.calls.count }, expected: 1)
        XCTAssertEqual(service.observable.snapshot.cpuUsage.value, 42)
        service.sleep()
        XCTAssertEqual(service.observable.snapshot.cpuUsage.value, 42,
                       "a just-sampled value stays as a cached reading across sleep")
        service.stopAll()
    }

    func testDemandChangeDuringReadRequestsNewFamilyImmediately() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: recorder.waitingReader())
        service.begin(.panel, metrics: [.cpuUsage])
        await awaitReadingStarted(recorder)
        XCTAssertEqual(recorder.calls[0], [.cpuUsage])

        // The card gains the sensor tiles while the usage read is in flight.
        service.begin(.panel, metrics: [.cpuUsage, .cpuTemperature, .fanRPM(index: 0)])
        recorder.continuations[0].resume(returning: .empty)
        await awaitReadingStarted(recorder, count: 2)
        XCTAssertEqual(recorder.calls.count, 2)
        XCTAssertTrue(recorder.calls[1].contains(.cpuTemperature))
        XCTAssertTrue(recorder.calls[1].contains(.fanRPM(index: 0)))
        recorder.continuations[1].resume(returning: .empty)
        service.stopAll()
    }

    func testReopenAfterStopWaitsForOutstandingPhysicalRead() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: recorder.waitingReader())
        service.begin(.panel, metrics: [.cpuUsage])
        await awaitReadingStarted(recorder)
        service.end(.panel)
        // Reopen immediately: the old physical read cannot be canceled, so the
        // service must queue the new epoch rather than start a second read.
        service.begin(.panel, metrics: [.cpuUsage])
        await drain()
        XCTAssertEqual(recorder.calls.count, 1, "no overlapping physical read")

        recorder.continuations[0].resume(returning: snapshot(usage: 11, at: clock.date))
        await awaitReadingStarted(recorder, count: 2)
        XCTAssertEqual(recorder.calls.count, 2)
        recorder.continuations[1].resume(returning: snapshot(usage: 22, at: clock.date))
        await drain()
        XCTAssertEqual(service.observable.snapshot.cpuUsage.value, 22)
        service.stopAll()
    }

    func testRepeatedEmptyReadsAgeOldValueToStaleNotPermanentMeasured() async {
        let clock = Clock()
        var first = HardwareMetricsSnapshot.empty
        first.samples[.cpuUsage] = .init(value: 30, unit: .percent, sampledAt: clock.date,
                                         source: .mach, availability: .measured)
        let scripted = ScriptedReader([first, .empty, .empty, .empty, .empty, .empty])
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: scripted.reader())
        service.begin(.panel, metrics: [.cpuUsage])
        await awaitSettledUntil(service) { scripted.calls >= 1 }
        XCTAssertEqual(service.observable.snapshot.cpuUsage.value, 30)
        // Keep ticking with empty frames well past the freshness window.
        for _ in 0..<6 {
            clock.advance(2)
            service.refreshIfNeeded(forceFamilies: [])
            await awaitSettledUntil(service) { !service.isAwaitingReadForTesting }
        }
        XCTAssertEqual(service.observable.snapshot.cpuUsage.availability, .stale)
        XCTAssertEqual(service.observable.snapshot.cpuUsage.value, 30,
                       "within the cache window the last value is shown dimmed, never as live")
        service.stopAll()
    }

    func testCollectingFirstTickAfterReopenDoesNotEraseCachedCPU() async {
        let clock = Clock()
        var measured = HardwareMetricsSnapshot.empty
        measured.samples[.cpuUsage] = .init(value: 42, unit: .percent, sampledAt: clock.date,
                                            source: .mach, availability: .measured)
        var collecting = HardwareMetricsSnapshot.empty
        collecting.samples[.cpuUsage] = .init(unit: .percent, source: .mach,
                                              availability: .collecting)   // baseline rebuild
        var fresh = HardwareMetricsSnapshot.empty
        fresh.samples[.cpuUsage] = .init(value: 55, unit: .percent, sampledAt: clock.date,
                                         source: .mach, availability: .measured)
        let scripted = ScriptedReader([measured, collecting, fresh])
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: scripted.reader())
        service.begin(.panel, metrics: [.cpuUsage])
        await awaitSettledUntil(service) { scripted.calls >= 1 }
        XCTAssertEqual(service.observable.snapshot.cpuUsage.value, 42)

        service.end(.panel)
        clock.advance(30)
        service.begin(.panel, metrics: [.cpuUsage])
        await awaitSettledUntil(service) { scripted.calls >= 2 }
        XCTAssertEqual(service.observable.snapshot.cpuUsage.value, 42,
                       "the baseline-rebuild tick must not wipe the cached CPU reading")
        XCTAssertEqual(service.observable.snapshot.cpuUsage.availability, .stale)

        clock.advance(2)
        service.refreshIfNeeded(forceFamilies: [])
        await awaitSettledUntil(service) { scripted.calls >= 3 }
        XCTAssertEqual(service.observable.snapshot.cpuUsage.value, 55)
        service.stopAll()
    }

    func testExpiredSnapshotHidesMeasuredValueAndProgressNeverFabricatesUnknown() {
        let sample = HardwareMetricSample(value: 65, unit: .celsius,
                                          sampledAt: Date(timeIntervalSince1970: 0),
                                          source: .smc, availability: .measured)
        let expired = sample.expiring(at: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(expired.availability, .stale)
        XCTAssertEqual(expired.value, 65, "cached value is kept inside the cache window")
        XCTAssertEqual(MetricProgressMapper.temperature(expired) ?? -1, 0.5, accuracy: 0.001,
                       "cached stale values still draw their dimmed bar")
        XCTAssertEqual(MetricProgressMapper.temperature(sample), 0.5)

        let tooOld = sample.expiring(at: Date(timeIntervalSince1970: 0).addingTimeInterval(400))
        XCTAssertEqual(tooOld.availability, .stale)
        XCTAssertNil(tooOld.value, "past cacheLifetime the number is dropped")

        let rpmWithoutMax = HardwareMetricSample(value: 1_000, unit: .rpm, source: .smc,
                                                 availability: .measured)
        XCTAssertNil(MetricProgressMapper.rpm(rpmWithoutMax),
                     "no reliable maximum RPM -> no invented proportion")
        let nanUsage = HardwareMetricSample(value: .nan, unit: .percent, source: .mach,
                                            availability: .measured)
        XCTAssertNil(MetricProgressMapper.percent(nanUsage))
    }

    func testFanSummaryPicksHottestAndUsesItsOwnMaximum() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.fanCount = 2
        snapshot.samples[.fanRPM(index: 0)] = .init(
            value: 1_000, unit: .rpm, sampledAt: Date(), source: .smc,
            availability: .measured, metadata: .init(maximum: 4_000, minimum: 1_000))
        snapshot.samples[.fanRPM(index: 1)] = .init(
            value: 2_450, unit: .rpm, sampledAt: Date(), source: .smc,
            availability: .measured, metadata: .init(maximum: 5_000, minimum: 1_400))
        let summary = snapshot.fanSummarySample
        XCTAssertEqual(summary.availability, .measured)
        XCTAssertEqual(summary.value, 2_450)
        XCTAssertEqual(summary.metadata.maximum, 5_000, "uses the hottest fan's own maximum")
        XCTAssertFalse(summary.metadata.isFanless)
        XCTAssertEqual(MetricProgressMapper.rpm(summary) ?? -1, 0.49, accuracy: 0.001)
    }

    func testFanCountUnknownIsCollectingNotFanless() {
        let snapshot = HardwareMetricsSnapshot.empty
        let summary = snapshot.fanSummarySample
        XCTAssertEqual(summary.availability, .collecting)
        XCTAssertFalse(summary.metadata.isFanless,
                       "no fan data yet must never be presented as a fanless Mac")
    }

    func testFansPresentButUnreadableIsTemporarilyUnavailableNotZero() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.fanCount = 2
        snapshot.samples[.fanRPM(index: 0)] = .init(
            unit: .rpm, source: .smc, availability: .temporarilyUnavailable)
        snapshot.samples[.fanRPM(index: 1)] = .init(
            unit: .rpm, source: .smc, availability: .temporarilyUnavailable)
        XCTAssertEqual(snapshot.fanSummarySample.availability, .temporarilyUnavailable)
        XCTAssertNil(MetricProgressMapper.rpm(snapshot.fanSummarySample))
    }

    func testStaleFanKeepsStaleReason() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.fanCount = 1
        snapshot.samples[.fanRPM(index: 0)] = .init(
            unit: .rpm, source: .smc, availability: .stale)
        XCTAssertEqual(snapshot.fanSummarySample.availability, .stale)
    }

    func testFanlessSnapshotIsUnsupportedNotZero() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.fanCount = 0
        snapshot.samples[.fanRPM(index: 0)] = .init(
            unit: .rpm, source: .smc, availability: .unsupported,
            metadata: .init(isFanless: true))
        let summary = snapshot.fanSummarySample
        XCTAssertNil(summary.value)
        XCTAssertTrue(summary.metadata.isFanless)
        XCTAssertEqual(summary.availability, .unsupported)
        XCTAssertNil(MetricProgressMapper.rpm(summary))
    }



    func testPanelDemandUsesConfiguredCadence() async {
        let clock = Clock()
        let service = HardwareMetricsService(automaticScheduling: false, now: { clock.date }, reader: { _, _ in .empty })
        service.panelIntervalSeconds = 5
        service.begin(.panel, metrics: [.networkDownload])
        XCTAssertEqual(service.currentTickIntervalForTesting, 5, "panel-open cadence is configurable")
        service.begin(.menuBarArc, metrics: [.networkDownload])
        XCTAssertEqual(service.currentTickIntervalForTesting, 1, "a second consumer keeps the fast cadence")
        service.end(.menuBarArc)
        XCTAssertEqual(service.currentTickIntervalForTesting, 5)
        service.stopAll()
    }

    func testBackgroundDemandUsesConfiguredCadence() async {
        let clock = Clock()
        let service = HardwareMetricsService(automaticScheduling: false, now: { clock.date }, reader: { _, _ in .empty })
        service.backgroundIntervalSeconds = 30
        service.begin(.background, metrics: [.networkDownload])
        XCTAssertEqual(service.currentTickIntervalForTesting, 30)
        service.begin(.panel, metrics: [.networkDownload])
        XCTAssertEqual(service.currentTickIntervalForTesting, 1, "an open panel overrides background cadence")
        service.end(.panel)
        XCTAssertEqual(service.currentTickIntervalForTesting, 30)
        service.stopAll()
    }

    func testSummarySnapshotKeepsLastKnownValueWithinCacheLifetime() {
        let observable = HardwareMonitorObservable()
        let t0 = Date(timeIntervalSince1970: 1_000)
        var snap = HardwareMetricsSnapshot.empty
        snap.samples[.networkDownload] = HardwareMetricSample(
            value: 1_000_000, unit: .bytesPerSecond, sampledAt: t0, source: .network, availability: .measured)
        observable.update(snap, now: t0)
        // Still within the 300 s cache: the previous reading is shown (dimmed).
        observable.markStale(now: t0.addingTimeInterval(100))
        XCTAssertEqual(observable.summarySnapshot(at: t0.addingTimeInterval(100)).networkDownload.value, 1_000_000)
        XCTAssertEqual(observable.summarySnapshot(at: t0.addingTimeInterval(100)).networkDownload.availability, .stale)
        // Past cacheLifetime the value is dropped rather than shown indefinitely.
        observable.markStale(now: t0.addingTimeInterval(400))
        XCTAssertNil(observable.snapshot.samples[.networkDownload]?.value)
        XCTAssertNil(observable.summarySnapshot(at: t0.addingTimeInterval(400)).networkDownload.value)
    }

    func testPressureSamplesImmediatelyAtTwoSecondCadenceAndClearsOnLastEnd() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date }, reader: recorder.waitingReader())
        service.begin(.menuBarArc, metrics: [.memoryPressure])
        XCTAssertEqual(service.currentTickIntervalForTesting, 2)
        await awaitReadingStarted(recorder)
        XCTAssertEqual(recorder.calls, [[.memoryPressure]])
        guard let first = recorder.continuations.first else { return XCTFail("first sample missing") }
        first.resume(returning: .init(memoryPressure: .init(level: .normal, sampledAt: clock.date)))
        await awaitSettled(service, recorder)
        XCTAssertEqual(service.observable.snapshot.memoryPressure?.level, .normal)

        clock.advance(1)
        service.refreshIfNeeded(forceFamilies: [])
        XCTAssertFalse(service.isAwaitingReadForTesting)
        clock.advance(1)
        service.refreshIfNeeded(forceFamilies: [])
        await awaitReadingStarted(recorder, count: 2)
        XCTAssertEqual(recorder.calls, [[.memoryPressure], [.memoryPressure]])
        guard recorder.continuations.count == 2 else { return XCTFail("second sample missing") }

        service.end(.menuBarArc)
        XCTAssertNil(service.observable.snapshot.memoryPressure)
        recorder.continuations[1].resume(returning: .init(memoryPressure: .init(level: .critical, sampledAt: clock.date)))
        await awaitSettled(service, recorder)
        XCTAssertFalse(service.isRunning)
        XCTAssertNil(service.observable.snapshot.memoryPressure)
    }

    func testDiskDemandUsesOneSecondCadenceAndStopsOnEnd() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false,
                                             now: { clock.date },
                                             reader: recorder.countingReader(usage: 0))
        service.begin(.panel, metrics: [.diskRead, .diskWrite])
        XCTAssertEqual(service.currentTickIntervalForTesting, 1,
                       "disk throughput samples once per second")
        await awaitSettled(service, recorder)
        XCTAssertEqual(recorder.calls.last, [.diskRead, .diskWrite])
        service.end(.panel)
        XCTAssertFalse(service.isRunning)
        let callCount = recorder.calls.count
        clock.advance(5)
        service.refreshIfNeeded(forceFamilies: [])
        await drain()
        XCTAssertEqual(recorder.calls.count, callCount, "ended disk demand must stop reads")
        service.stopAll()
    }

    /// A fast CPU icon (2 s) must not speed up disk I/O that only the slow panel
    /// (5 s) asked for, while the shared CPU metric follows the icon.
    func testSharedCPUAndIndependentPanelDeadlines() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false, now: { clock.date },
                                             reader: recorder.countingReader(usage: 10))
        service.panelIntervalSeconds = 5
        service.begin(.menuBarArc, metrics: [.cpuUsage])
        service.begin(.dock, metrics: [.cpuUsage])
        service.begin(.panel, metrics: [.cpuUsage, .diskRead, .diskWrite])

        XCTAssertEqual(service.intervalForTesting(.cpuUsage), 2,
                       "a 2 s icon consumer keeps the shared CPU metric fast")
        XCTAssertEqual(service.intervalForTesting(.diskRead), 5,
                       "disk is only read by the 5 s panel")
        XCTAssertEqual(service.currentTickIntervalForTesting, 2)
        service.stopAll()

        // A slow panel sensor that no icon needs stays at the panel cadence even
        // while an unrelated fast metric is also demanded.
        service.panelIntervalSeconds = 3
        service.begin(.panel, metrics: [.cpuTemperature])
        service.begin(.menuBarCenter, metrics: [.networkDownload])
        XCTAssertEqual(service.intervalForTesting(.cpuTemperature), 4,
                       "a 3 s panel cannot push a 4 s sensor faster")
        XCTAssertEqual(service.intervalForTesting(.networkDownload), 1)
        service.stopAll()
    }

    func testSwitchingDetailDropsLatePayloadFromPreviousPage() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false, now: { clock.date },
                                             reader: recorder.waitingReader())
        service.begin(.panel, metrics: [.gpuUsage, .memoryUsage])
        await awaitReadingStarted(recorder)

        service.setDetailDemand(.gpu)
        service.setDetailDemand(.memory)
        var late = HardwareMetricsSnapshot.empty
        late.gpuDetail = GPUDetailReading(deviceName: "Apple M3 Max", usage: 37,
                                          rendererUtilization: 42, tilerUtilization: 35,
                                          inUseSystemMemoryBytes: 4_200_000_000, sampledAt: clock.date)
        recorder.continuations[0].resume(returning: late)
        await drain(80)

        XCTAssertNil(service.observable.snapshot.gpuDetail,
                     "a read started for the previous detail must not restore its payload")
        XCTAssertNil(service.observable.snapshot.memoryDetail)
        if recorder.calls.count > 1, recorder.continuations.count > 1 {
            recorder.continuations[1].resume(returning: .empty)
            await drain()
        }
        service.stopAll()
    }

    func testSlowReadParksTheLoopInsteadOfPollingEvery50ms() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false, now: { clock.date },
                                             reader: recorder.waitingReader())
        service.begin(.panel, metrics: [.cpuUsage])
        await awaitReadingStarted(recorder)
        clock.advance(3)

        XCTAssertEqual(service.currentWakeDelayForTesting, 30,
                       "an overdue metric must not spin the main actor while the read is outstanding")
        recorder.continuations[0].resume(returning: .empty)
        await drain()
        service.stopAll()
    }

    func testShrinkingDemandPrunesAndStopsReadingTheRemovedMetric() async {
        let clock = Clock()
        let recorder = Recorder()
        let service = HardwareMetricsService(automaticScheduling: false, now: { clock.date },
                                             reader: recorder.waitingReader())
        service.begin(.panel, metrics: [.cpuUsage, .gpuUsage])
        await awaitReadingStarted(recorder)
        XCTAssertEqual(recorder.calls[0], Set([.cpuUsage, .gpuUsage]))
        recorder.continuations[0].resume(returning: .empty)
        await drain()

        // Shrink the demand: GPU loses its last consumer.
        service.begin(.panel, metrics: [.cpuUsage])
        XCTAssertNil(service.observable.snapshot.samples[.gpuUsage],
                     "a metric with no consumer must be removed from the live snapshot")
        service.forceRefresh()
        await awaitReadingStarted(recorder, count: 2)
        XCTAssertEqual(recorder.calls[1], Set([.cpuUsage]),
                       "the removed metric must never be requested again")
        recorder.continuations[1].resume(returning: .empty)
        await drain()

        service.end(.panel)
        XCTAssertFalse(service.isRunning)
        XCTAssertTrue(service.demands.isEmpty)
        service.stopAll()
    }
}
