import Foundation
import Testing
@testable import StatusTrioCore

private actor FakeTopAppsSampler: TopAppsSampling {
    private(set) var reads: [TopAppMetric] = []
    private(set) var resetCount = 0
    var results: [TopAppMetric: TopAppsReadResult] = [:]
    private var blockNext = 0
    private var pending: [CheckedContinuation<Void, Never>] = []

    func setResults(_ results: [TopAppMetric: TopAppsReadResult]) {
        self.results = results
    }

    func blockNextReads(_ count: Int) {
        blockNext = count
    }

    func releaseAll() {
        let continuations = pending
        pending.removeAll()
        for continuation in continuations { continuation.resume() }
    }

    func read(_ metric: TopAppMetric, applications: [ProcessApplication]) async -> TopAppsReadResult {
        reads.append(metric)
        if blockNext > 0 {
            blockNext -= 1
            await withCheckedContinuation { continuation in
                pending.append(continuation)
            }
        }
        return results[metric] ?? .measured([])
    }

    func reset() async { resetCount += 1 }

    func readCount() -> Int { reads.count }
    func lastMetric() -> TopAppMetric? { reads.last }
}

private actor SleepRecorder {
    private(set) var durations: [Duration] = []

    var count: Int { durations.count }
    var last: Duration? { durations.last }

    func record(_ duration: Duration) { durations.append(duration) }
}

@MainActor
struct TopAppsServiceTests {
    private let app = ProcessApplication(pid: 1, path: "/Applications/A.app", bundleID: "a", name: "A")

    private func makeService(_ sampler: FakeTopAppsSampler) -> TopAppsService {
        TopAppsService(sampler: sampler,
                       applications: { [] },
                       automaticScheduling: false)
    }

    @Test func testNoDemandDoesNotRead() async throws {
        let sampler = FakeTopAppsSampler()
        let service = makeService(sampler)
        try await Task.sleep(for: .milliseconds(40))
        #expect(await sampler.readCount() == 0)
        #expect(service.observable.state == .idle)
    }

    @Test func testOneSecondCadenceNeverOverlaps() async throws {
        let sampler = FakeTopAppsSampler()
        await sampler.blockNextReads(1)
        let service = makeService(sampler)
        service.setDemand(.cpu)
        let first = Task { await service.sampleNowForTesting() }

        for _ in 0..<100 {
            if await sampler.readCount() == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await sampler.readCount() == 1)
        #expect(service.isReadInFlightForTesting)

        await service.sampleNowForTesting()
        #expect(await sampler.readCount() == 1)

        await sampler.releaseAll()
        await first.value
        #expect(!service.isReadInFlightForTesting)
    }

    @Test func testSwitchCancelsOldSessionAndDropsLateResult() async throws {
        let sampler = FakeTopAppsSampler()
        await sampler.blockNextReads(1)
        await sampler.setResults([
            .cpu: .measured([TopAppRow(id: .application(path: "/Applications/A.app"),
                                       name: "A", applicationPath: "/Applications/A.app",
                                       value: 42, upload: nil)]),
            .network: .measured([TopAppRow(id: .application(path: "/Applications/B.app"),
                                           name: "B", applicationPath: "/Applications/B.app",
                                           value: 1_000, upload: 500)])
        ])
        let service = makeService(sampler)
        service.setDemand(.cpu)
        let first = Task { await service.sampleNowForTesting() }
        for _ in 0..<100 {
            if await sampler.readCount() == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        service.setDemand(.network)
        #expect(service.observable.state == .collecting(.network))
        await sampler.releaseAll()
        await first.value
        #expect(service.observable.state == .collecting(.network))

        await service.sampleNowForTesting()
        #expect(service.observable.state == .measured(.network, [
            TopAppRow(id: .application(path: "/Applications/B.app"),
                      name: "B", applicationPath: "/Applications/B.app",
                      value: 1_000, upload: 500)
        ]))
    }

    @Test func testSleepReopenAndStopClearBaselines() async throws {
        let sampler = FakeTopAppsSampler()
        let service = makeService(sampler)
        service.setDemand(.gpu)

        service.sleep()
        #expect(service.isAsleep)
        #expect(service.observable.state == .collecting(.gpu))
        for _ in 0..<100 {
            if await sampler.resetCount >= 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await sampler.resetCount == 1)

        service.wake()
        #expect(!service.isAsleep)
        #expect(service.observable.state == .collecting(.gpu))

        service.stop()
        #expect(service.isStopped)
        #expect(service.observable.state == .idle)
        for _ in 0..<100 {
            if await sampler.resetCount >= 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await sampler.resetCount == 2)
    }

    @Test func testMemoryPollsLessOftenThanOtherMetrics() async throws {
        let sampler = FakeTopAppsSampler()
        let recorder = SleepRecorder()
        let service = TopAppsService(sampler: sampler,
                                     applications: { [] },
                                     automaticScheduling: true,
                                     sleepFor: { duration in
                                         await recorder.record(duration)
                                         try await Task.sleep(for: .seconds(60))
                                     },
                                     clock: { 0 })
        service.setDemand(.memory)
        for _ in 0..<100 {
            if await recorder.count > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let memorySleep = await recorder.last
        #expect(memorySleep?.components.seconds == 6)
        service.stop()

        let cpuSampler = FakeTopAppsSampler()
        let cpuRecorder = SleepRecorder()
        let cpuService = TopAppsService(sampler: cpuSampler,
                                        applications: { [] },
                                        automaticScheduling: true,
                                        sleepFor: { duration in
                                            await cpuRecorder.record(duration)
                                            try await Task.sleep(for: .seconds(60))
                                        },
                                        clock: { 0 })
        cpuService.setDemand(.cpu)
        for _ in 0..<100 {
            if await cpuRecorder.count > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let cpuSleep = await cpuRecorder.last
        #expect(cpuSleep?.components.seconds == 2)
        cpuService.stop()
    }

    @Test func testFailureDoesNotKeepNumbersAsLive() async {
        let sampler = FakeTopAppsSampler()
        await sampler.setResults([.memory: .failed])
        let service = makeService(sampler)
        service.setDemand(.memory)
        await service.sampleNowForTesting()
        #expect(service.observable.state == .failed(.memory))

        await sampler.setResults([.memory: .measured([])])
        await service.sampleNowForTesting()
        #expect(service.observable.state == .measured(.memory, []))
    }

    @Test func testZeroRowsStayUntilANewAppReplacesThem() {
        func row(_ name: String, _ value: Double) -> TopAppRow {
            TopAppRow(id: .process(ProcessIdentity(pid: Int32(abs(name.hashValue % 10_000)), startedAt: 1)),
                      name: name, applicationPath: nil, value: value, upload: nil)
        }
        let two = TopAppsService.mergedRows(previous: [], incoming: [row("A", 10), row("B", 5)], limit: 8)
        #expect(two.map(\.name) == ["A", "B"])

        let dropped = TopAppsService.mergedRows(previous: two, incoming: [row("A", 10)], limit: 8)
        #expect(dropped.map(\.name) == ["A", "B"])
        #expect(dropped.last?.value == 0)

        let replaced = TopAppsService.mergedRows(previous: dropped,
                                                 incoming: [row("A", 10), row("C", 3)], limit: 2)
        #expect(replaced.map(\.name) == ["A", "C"])
    }
}