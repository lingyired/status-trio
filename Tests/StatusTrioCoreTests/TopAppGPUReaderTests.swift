import Foundation
import Testing
@testable import StatusTrioCore

struct TopAppGPUReaderTests {
    private struct ReaderStub: ProcessMetadataReading {
        func metadata(for pid: Int32, fallbackName: String) -> ProcessMetadata? {
            ProcessMetadata(identity: ProcessIdentity(pid: pid, startedAt: 99),
                            name: fallbackName, executablePath: nil, responsiblePID: nil)
        }
    }

    private func client(entryID: UInt64, pid: Int32, gpuTime: UInt64,
                        queueCount: Int = 1, startedAt: UInt64 = 10) -> GPUClientCounter {
        GPUClientCounter(entryID: entryID,
                         metadata: ProcessMetadata(identity: ProcessIdentity(pid: pid, startedAt: startedAt),
                                                   name: "P\(pid)", executablePath: nil, responsiblePID: nil),
                         gpuTime: gpuTime, queueCount: queueCount)
    }

    @Test func testGpuTimeDeltaIsPercentage() {
        var tracker = GPUAppUsageTracker()
        _ = tracker.sample([client(entryID: 1, pid: 10, gpuTime: 1_000_000_000)], at: 1_000_000_000)
        let samples = tracker.sample([client(entryID: 1, pid: 10, gpuTime: 1_500_000_000)],
                                     at: 2_000_000_000)
        #expect(samples?.count == 1)
        #expect(samples?.first?.value == 50)
    }

    @Test func testSamePIDMultipleClientsAggregateToApplication() {
        var tracker = GPUAppUsageTracker()
        let first = [client(entryID: 1, pid: 10, gpuTime: 0), client(entryID: 2, pid: 10, gpuTime: 0)]
        _ = tracker.sample(first, at: 1_000_000_000)
        let second = [client(entryID: 1, pid: 10, gpuTime: 250_000_000),
                      client(entryID: 2, pid: 10, gpuTime: 250_000_000)]
        let samples = tracker.sample(second, at: 2_000_000_000) ?? []
        let applications = [ProcessApplication(pid: 10, path: "/Applications/Game.app", bundleID: "g", name: "Game")]
        let rows = TopAppAggregator.rows(metric: .gpu, samples: samples, applications: applications)
        #expect(rows.count == 1)
        #expect(rows.first?.value == 50)
    }

    @Test func testGPUClientOrQueueChangeReprimes() {
        var tracker = GPUAppUsageTracker()
        _ = tracker.sample([client(entryID: 1, pid: 10, gpuTime: 100, queueCount: 2)], at: 1_000_000_000)

        #expect(tracker.sample([client(entryID: 2, pid: 10, gpuTime: 200, queueCount: 2)],
                               at: 2_000_000_000)?.isEmpty == true)
        #expect(tracker.sample([client(entryID: 2, pid: 11, gpuTime: 300, queueCount: 2)],
                               at: 3_000_000_000)?.isEmpty == true)
        #expect(tracker.sample([client(entryID: 2, pid: 11, gpuTime: 400, queueCount: 3)],
                               at: 4_000_000_000)?.isEmpty == true)
        #expect(tracker.sample([client(entryID: 2, pid: 11, gpuTime: 300, queueCount: 3)],
                               at: 5_000_000_000)?.isEmpty == true)
    }

    @Test func testTooShortOrLongSampleDoesNotSpike() {
        var tracker = GPUAppUsageTracker()
        _ = tracker.sample([client(entryID: 1, pid: 10, gpuTime: 0)], at: 1_000_000_000)
        #expect(tracker.sample([client(entryID: 1, pid: 10, gpuTime: 900_000_000)],
                               at: 1_249_999_999) == nil)
        let longGap = tracker.sample([client(entryID: 1, pid: 10, gpuTime: 2_000_000_000)],
                                     at: 5_000_000_001)
        #expect(longGap == nil)
    }

    @Test func testMissingAppUsageAndUnsupportedArchitecture() {
        let properties: [String: Any] = ["IOUserClientCreator": "pid 10, Game"]
        let noUsage = GPUClientParser.parse(properties: properties, entryID: 1, metadataReader: ReaderStub())
        #expect(noUsage == .noUsage)

        let emptyUsage: [String: Any] = ["IOUserClientCreator": "pid 10, Game", "AppUsage": []]
        #expect(GPUClientParser.parse(properties: emptyUsage, entryID: 1, metadataReader: ReaderStub()) == .noUsage)

        let unsupported = TopAppGPUReader(isSupported: { false }).read()
        if case .failure(.unsupported) = unsupported {
            #expect(Bool(true))
        } else {
            Issue.record("expected unsupported, got \(unsupported)")
        }
    }

    @Test func testParseClientCreatorAndTotals() {
        #expect(GPUClientParser.parseCreator("pid 623, WindowServer")?.pid == 623)
        #expect(GPUClientParser.parseCreator("pid 623, WindowServer")?.name == "WindowServer")
        #expect(GPUClientParser.parseCreator("garbage") == nil)

        let properties: [String: Any] = [
            "IOUserClientCreator": "pid 10, Game",
            "AppUsage": [
                ["accumulatedGPUTime": NSNumber(value: 100), "accumulatedGPUQueueCount": NSNumber(value: 2)],
                ["accumulatedGPUTime": NSNumber(value: 50)]
            ]
        ]
        guard case .client(let client) = GPUClientParser.parse(properties: properties, entryID: 7, metadataReader: ReaderStub()) else {
            Issue.record("expected client")
            return
        }
        #expect(client.gpuTime == 150)
        #expect(client.queueCount == 2)
        #expect(client.entryID == 7)
    }

    @Test func testResetMakesTheNextFramePrimeAndTheFollowingFrameUseTheNewBaseline() {
        var tracker = GPUAppUsageTracker()
        _ = tracker.sample([client(entryID: 1, pid: 10, gpuTime: 100)], at: 1_000_000_000)
        tracker.reset()
        #expect(tracker.sample([client(entryID: 1, pid: 10, gpuTime: 1_000_000_000)],
                               at: 2_000_000_000) == nil)
        let samples = tracker.sample([client(entryID: 1, pid: 10, gpuTime: 1_500_000_000)],
                                     at: 3_000_000_000)
        #expect(samples?.first?.value == 50)
    }
}
