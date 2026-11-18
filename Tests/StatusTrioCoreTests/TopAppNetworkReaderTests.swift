import Foundation
import Testing
@testable import StatusTrioCore

struct TopAppNetworkReaderTests {
    private func metadata(pid: Int32, name: String = "Proc", startedAt: UInt64? = 10) -> ProcessMetadata {
        ProcessMetadata(identity: ProcessIdentity(pid: pid, startedAt: startedAt),
                        name: name, executablePath: nil, responsiblePID: nil)
    }

    private func counter(pid: Int32, name: String = "Proc", startedAt: UInt64? = 10,
                         received: UInt64, sent: UInt64) -> NetworkProcessCounter {
        NetworkProcessCounter(metadata: metadata(pid: pid, name: name, startedAt: startedAt),
                              received: received, sent: sent)
    }

    @Test func testFirstSampleOnlyPrimesBaseline() {
        var tracker = NetworkAppUsageTracker()
        #expect(tracker.sample([counter(pid: 1, received: 1_000, sent: 500)],
                               at: 1_000_000_000) == nil)
    }

    @Test func testRatesUseActualTwoSecondInterval() {
        var tracker = NetworkAppUsageTracker()
        _ = tracker.sample([counter(pid: 1, received: 1_000, sent: 500)], at: 1_000_000_000)
        let samples = tracker.sample([counter(pid: 1, received: 5_096, sent: 1_524)],
                                     at: 3_000_000_000)
        #expect(samples?.count == 1)
        #expect(samples?.first?.value == 2_048)
        #expect(samples?.first?.upload == 512)
    }

    @Test func testRestartCounterResetAndLongGapReprime() {
        var tracker = NetworkAppUsageTracker()
        _ = tracker.sample([counter(pid: 1, startedAt: 10, received: 1_000, sent: 1_000)], at: 1_000_000_000)

        // Same PID, new start time: not the same process.
        let restarted = tracker.sample([counter(pid: 1, startedAt: 20, received: 5_000, sent: 5_000)],
                                        at: 2_000_000_000)
        #expect(restarted?.isEmpty == true)
        let afterRestart = tracker.sample([counter(pid: 1, startedAt: 20, received: 6_000, sent: 5_500)],
                                          at: 3_000_000_000)
        #expect(afterRestart?.first?.value == 1_000)

        // Counter reset at the same identity: reprime, then rate from the new base.
        let reset = tracker.sample([counter(pid: 1, startedAt: 20, received: 10, sent: 10)],
                                   at: 4_000_000_000)
        #expect(reset?.isEmpty == true)

        // A gap over three seconds must not create a spike.
        let longGap = tracker.sample([counter(pid: 1, startedAt: 20, received: 2_000, sent: 2_000)],
                                     at: 8_000_000_000)
        #expect(longGap == nil)
    }

    @Test func testUnstableIdentityNeverProducesRates() {
        var tracker = NetworkAppUsageTracker()
        _ = tracker.sample([counter(pid: 1, startedAt: nil, received: 1_000, sent: 1_000)], at: 1_000_000_000)
        let samples = tracker.sample([counter(pid: 1, startedAt: nil, received: 9_000, sent: 9_000)],
                                     at: 2_000_000_000)
        #expect(samples?.isEmpty == true)
    }

    @Test func testNamesWithDotsSpacesAndQuotedCommas() {
        let output = """
        ,bytes_in,bytes_out,
        "Google Chrome Helper.123",100,200,
        com.apple.Safari.456,300,400,
        "Name, with comma.789",500,600,
        """
        let result = TopAppNetworkParser.parse(Data(output.utf8))
        guard case .success(let rows) = result else {
            Issue.record("expected parsed rows")
            return
        }
        #expect(rows.map(\.pid) == [123, 456, 789])
        #expect(rows[0].name == "Google Chrome Helper")
        #expect(rows[1].name == "com.apple.Safari")
        #expect(rows[2].name == "Name, with comma")
    }

    @Test func testMissingHeaderOrCounterFails() {
        let result = TopAppNetworkParser.parse(Data("launchd.1,0,0,".utf8))
        if case .failure(.malformedOutput) = result {
            #expect(Bool(true))
        } else {
            Issue.record("expected malformedOutput")
        }
    }

    @Test func testTrackerThenAggregatorMergesApplication() {
        var tracker = NetworkAppUsageTracker()
        let first = [counter(pid: 1, name: "A One", received: 1_000, sent: 1_000),
                     counter(pid: 2, name: "A Two", received: 1_000, sent: 1_000)]
        _ = tracker.sample(first, at: 1_000_000_000)
        let second = [counter(pid: 1, name: "A One", received: 2_048, sent: 1_536),
                      counter(pid: 2, name: "A Two", received: 1_512, sent: 1_024)]
        let samples = tracker.sample(second, at: 2_000_000_000) ?? []

        let applications = [ProcessApplication(pid: 1, path: "/Applications/A.app", bundleID: "a", name: "A"),
                            ProcessApplication(pid: 2, path: "/Applications/A.app", bundleID: "a", name: "A")]
        let rows = TopAppAggregator.rows(metric: .network, samples: samples, applications: applications)
        #expect(rows.count == 1)
        #expect(rows.first?.value == 1_560)
        #expect(rows.first?.upload == 560)
    }
}
