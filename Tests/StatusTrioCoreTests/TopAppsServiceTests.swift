import Foundation
import Testing
@testable import StatusTrioCore

private actor FakeTopAppsSampler: TopAppsSampling {
    enum Event: Equatable, Sendable {
        case readStarted(TopAppMetric)
        case readFinished(TopAppMetric)
        case resetStarted
        case resetFinished
    }

    private(set) var reads: [TopAppMetric] = []
    private(set) var events: [Event] = []
    private(set) var resetCount = 0
    private var results: [TopAppMetric: TopAppsReadResult] = [:]
    private var remainingReadBlocks = 0
    private var remainingResetBlocks = 0
    private var readGates: [CheckedContinuation<Void, Never>] = []
    private var resetGates: [CheckedContinuation<Void, Never>] = []

    func setResults(_ results: [TopAppMetric: TopAppsReadResult]) {
        self.results = results
    }

    func blockNextReads(_ count: Int) {
        remainingReadBlocks = count
    }

    func blockNextResets(_ count: Int) {
        remainingResetBlocks = count
    }

    func releaseNextRead() {
        guard !readGates.isEmpty else { return }
        readGates.removeFirst().resume()
    }

    func releaseNextReset() {
        guard !resetGates.isEmpty else { return }
        resetGates.removeFirst().resume()
    }

    func releaseAll() {
        let reads = readGates
        readGates.removeAll()
        let resets = resetGates
        resetGates.removeAll()
        for continuation in reads { continuation.resume() }
        for continuation in resets { continuation.resume() }
    }

    func read(_ metric: TopAppMetric, applications: [ProcessApplication]) async -> TopAppsReadResult {
        reads.append(metric)
        events.append(.readStarted(metric))
        if remainingReadBlocks > 0 {
            remainingReadBlocks -= 1
            await withCheckedContinuation { continuation in
                readGates.append(continuation)
            }
        }
        events.append(.readFinished(metric))
        return results[metric] ?? .measured([])
    }

    func reset() async {
        resetCount += 1
        events.append(.resetStarted)
        if remainingResetBlocks > 0 {
            remainingResetBlocks -= 1
            await withCheckedContinuation { continuation in
                resetGates.append(continuation)
            }
        }
        events.append(.resetFinished)
    }

    func readCount() -> Int { reads.count }
    func lastMetric() -> TopAppMetric? { reads.last }
    func eventLog() -> [Event] { events }
}

/// Runs the real cumulative trackers while making the physical read sequence
/// controllable, so a service-level test can prove which frame primes a new
/// baseline after a session ends.
private actor TrackerTopAppsSampler: TopAppsSampling {
    struct NetworkFrame: Sendable {
        let received: UInt64
        let sent: UInt64
        let at: UInt64
    }

    struct GPUFrame: Sendable {
        let gpuTime: UInt64
        let at: UInt64
    }

    private let metadata = ProcessMetadata(identity: ProcessIdentity(pid: 42, startedAt: 10),
                                           name: "A",
                                           executablePath: "/Applications/A.app",
                                           responsiblePID: nil)
    private var networkTracker = NetworkAppUsageTracker()
    private var gpuTracker = GPUAppUsageTracker()
    private var networkFrames: [NetworkFrame] = []
    private var gpuFrames: [GPUFrame] = []
    private var blockedReadNumbers: Set<Int> = []
    private var readGates: [CheckedContinuation<Void, Never>] = []

    private(set) var reads: [TopAppMetric] = []
    private(set) var resetCount = 0

    init(_ metric: TrackerSessionMetric) {
        switch metric {
        case .network:
            networkFrames = [
                NetworkFrame(received: 1_000, sent: 500, at: 1_000_000_000),
                NetworkFrame(received: 2_000, sent: 1_000, at: 2_000_000_000),
                NetworkFrame(received: 3_048, sent: 1_524, at: 3_000_000_000)
            ]
        case .gpu:
            gpuFrames = [
                GPUFrame(gpuTime: 0, at: 1_000_000_000),
                GPUFrame(gpuTime: 1_000_000_000, at: 2_000_000_000),
                GPUFrame(gpuTime: 1_500_000_000, at: 3_000_000_000)
            ]
        }
    }

    func blockRead(_ number: Int) {
        blockedReadNumbers.insert(number)
    }

    func releaseNextRead() {
        guard !readGates.isEmpty else { return }
        readGates.removeFirst().resume()
    }

    func read(_ metric: TopAppMetric, applications: [ProcessApplication]) async -> TopAppsReadResult {
        reads.append(metric)
        if blockedReadNumbers.contains(reads.count) {
            await withCheckedContinuation { continuation in
                readGates.append(continuation)
            }
        }

        switch metric {
        case .network:
            guard !networkFrames.isEmpty else { return .measured([]) }
            let frame = networkFrames.removeFirst()
            let counter = NetworkProcessCounter(metadata: metadata,
                                                received: frame.received,
                                                sent: frame.sent)
            return networkTracker.sample([counter], at: frame.at) == nil ? .collecting : .measured([])
        case .gpu:
            guard !gpuFrames.isEmpty else { return .measured([]) }
            let frame = gpuFrames.removeFirst()
            let client = GPUClientCounter(entryID: 7, metadata: metadata,
                                          gpuTime: frame.gpuTime, queueCount: 1)
            return gpuTracker.sample([client], at: frame.at) == nil ? .collecting : .measured([])
        case .cpu, .memory:
            return .measured([])
        }
    }

    func reset() async {
        resetCount += 1
        networkTracker.reset()
        gpuTracker.reset()
    }

    func readCount() -> Int { reads.count }
}

enum TrackerSessionMetric: Sendable {
    case gpu
    case network

    var metric: TopAppMetric {
        switch self {
        case .gpu: return .gpu
        case .network: return .network
        }
    }
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

    private func makeTrackedService(_ sampler: any TopAppsSampling) -> TopAppsService {
        TopAppsService(sampler: sampler,
                       applications: { [] },
                       automaticScheduling: true,
                       sleepFor: { _ in throw CancellationError() },
                       clock: { 0 })
    }

    private func waitFor(_ condition: @escaping @Sendable () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
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

    @Test func testMetricSweepDoesNotPublishThePreviousPageAndKeepsOneReadInFlight() async throws {
        let sampler = FakeTopAppsSampler()
        await sampler.blockNextReads(1)
        await sampler.setResults([
            .cpu: .measured([TopAppRow(id: .application(path: "/Applications/A.app"),
                                       name: "A", applicationPath: "/Applications/A.app",
                                       value: 42, upload: nil)]),
            .memory: .measured([TopAppRow(id: .application(path: "/Applications/C.app"),
                                          name: "C", applicationPath: "/Applications/C.app",
                                          value: 7, upload: nil)])
        ])
        let service = makeService(sampler)
        service.setDemand(.cpu)
        let first = Task { await service.sampleNowForTesting() }
        try await waitFor { await sampler.readCount() == 1 }

        service.setDemand(.gpu)
        service.setDemand(.network)
        service.setDemand(.memory)
        #expect(service.demand == .memory)
        #expect(service.observable.state == .collecting(.memory))

        await service.sampleNowForTesting()
        #expect(await sampler.readCount() == 1)
        #expect(service.isReadInFlightForTesting)

        await sampler.releaseNextRead()
        await first.value
        #expect(await sampler.readCount() == 1)
        #expect(service.observable.state == .collecting(.memory))

        await service.sampleNowForTesting()
        #expect(service.observable.state == .measured(.memory, [
            TopAppRow(id: .application(path: "/Applications/C.app"),
                      name: "C", applicationPath: "/Applications/C.app",
                      value: 7, upload: nil)
        ]))
    }

    @Test(arguments: [TopAppMetric.gpu, .network])
    func testSleepDuringReadWaitsForTheReadAndResetBeforeTheNextRead(_ metric: TopAppMetric) async throws {
        let sampler = FakeTopAppsSampler()
        await sampler.blockNextReads(2)
        await sampler.setResults([metric: .measured([])])
        let service = makeTrackedService(sampler)
        service.setDemand(metric)
        try await waitFor { await sampler.readCount() == 1 }

        await sampler.blockNextResets(1)
        service.sleep()
        service.wake()
        await sampler.releaseNextRead()

        try await waitFor { await sampler.eventLog().contains(.resetStarted) }
        #expect(await sampler.readCount() == 1)
        #expect(service.isReadInFlightForTesting)

        await sampler.releaseNextReset()
        try await waitFor { await sampler.readCount() == 2 }
        let events = await sampler.eventLog()
        #expect(Array(events.suffix(4)) == [.readFinished(metric),
                                           .resetStarted,
                                           .resetFinished,
                                           .readStarted(metric)])

        service.stop()
        await sampler.releaseNextRead()
        try await Task.sleep(for: .milliseconds(20))
        #expect(await sampler.readCount() == 2)
    }

    @Test func testCloseReopenSameMetricResetsAfterTheOldReadBeforeTheNextRead() async throws {
        let sampler = FakeTopAppsSampler()
        await sampler.blockNextReads(2)
        await sampler.setResults([.gpu: .measured([])])
        let service = makeTrackedService(sampler)
        service.setDemand(.gpu)
        try await waitFor { await sampler.readCount() == 1 }

        service.setDemand(nil)
        service.setDemand(.gpu)
        #expect(service.demand == .gpu)
        #expect(service.observable.state == .collecting(.gpu))
        await service.sampleNowForTesting()
        #expect(await sampler.readCount() == 1)

        await sampler.releaseNextRead()
        try await waitFor { await sampler.readCount() == 2 }
        let events = await sampler.eventLog()
        #expect(Array(events.suffix(4)) == [.readFinished(.gpu),
                                           .resetStarted,
                                           .resetFinished,
                                           .readStarted(.gpu)])
        #expect(service.observable.state == .collecting(.gpu))

        service.stop()
        await sampler.releaseNextRead()
        try await Task.sleep(for: .milliseconds(20))
        #expect(await sampler.readCount() == 2)
    }

    @Test(arguments: [TrackerSessionMetric.gpu, .network])
    func testSleepDuringCumulativeReadStartsTheNextSessionFromANewBaseline(
        _ session: TrackerSessionMetric
    ) async throws {
        let metric = session.metric
        let sampler = TrackerTopAppsSampler(session)
        await sampler.blockRead(1)
        await sampler.blockRead(3)
        await sampler.blockRead(4)
        let service = makeTrackedService(sampler)
        service.setDemand(metric)
        try await waitFor { await sampler.readCount() == 1 }

        service.sleep()
        service.wake()
        try await Task.sleep(for: .milliseconds(30))
        await sampler.releaseNextRead()

        try await waitFor { await sampler.readCount() == 3 }
        #expect(await sampler.resetCount == 2)
        #expect(service.observable.state == .collecting(metric))

        await sampler.releaseNextRead()
        for _ in 0..<200 {
            if service.observable.state == .measured(metric, []) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(service.observable.state == .measured(metric, []))
        #expect(await sampler.resetCount == 2)

        service.stop()
        await sampler.releaseNextRead()
        try await Task.sleep(for: .milliseconds(20))
    }

    @Test func testClosedDemandAndStopDoNotStartAnotherRead() async throws {
        let sampler = FakeTopAppsSampler()
        await sampler.blockNextReads(2)
        let service = makeTrackedService(sampler)
        service.setDemand(.gpu)
        try await waitFor { await sampler.readCount() == 1 }

        service.setDemand(nil)
        #expect(service.observable.state == .idle)
        await sampler.releaseNextRead()
        try await Task.sleep(for: .milliseconds(30))
        #expect(await sampler.readCount() == 1)
        #expect(!service.isReadInFlightForTesting)

        service.setDemand(.gpu)
        try await waitFor { await sampler.readCount() == 2 }
        service.stop()
        #expect(service.observable.state == .idle)
        await sampler.releaseNextRead()
        try await Task.sleep(for: .milliseconds(30))
        #expect(await sampler.readCount() == 2)
    }

    @Test func testSleepAndStopClearIdleBaselines() async throws {
        let sampler = FakeTopAppsSampler()
        let service = makeService(sampler)
        service.setDemand(.gpu)

        service.sleep()
        try await waitFor { await sampler.resetCount == 1 }
        #expect(service.isAsleep)
        #expect(service.observable.state == .collecting(.gpu))

        service.wake()
        service.stop()
        try await waitFor { await sampler.resetCount == 2 }
        #expect(await sampler.readCount() == 0)
        #expect(service.observable.state == .idle)
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