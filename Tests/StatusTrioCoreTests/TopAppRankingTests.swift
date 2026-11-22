import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct TopAppRankingTests {
    private func row(_ name: String, _ value: Double, upload: Double? = nil) -> TopAppRow {
        TopAppRow(id: .application(path: "/Applications/\(name).app"),
                  name: name, applicationPath: "/Applications/\(name).app",
                  value: value, upload: upload)
    }

    @Test func testSortsByValueDescending() {
        let rows = [row("A", 10), row("C", 30), row("B", 20)]
        #expect(TopAppRanking.sorted(rows, metric: .memory).map(\.name) == ["C", "B", "A"])
    }

    @Test(arguments: [TopAppMetric.cpu, .gpu, .memory])
    func testNewHighValueAppLandsInCorrectPosition(_ metric: TopAppMetric) {
        // Previous frame froze the order as A, B; a new heavy app must not be
        // appended at the bottom.
        let merged = TopAppsService.mergedRows(
            previous: [row("A", 10), row("B", 5)],
            incoming: [row("A", 10), row("B", 5), row("C", 20)],
            metric: metric, limit: 8)
        #expect(merged.map(\.name) == ["C", "A", "B"])
    }

    @Test func testValueChangeReordersRows() {
        let merged = TopAppsService.mergedRows(
            previous: [row("A", 10), row("B", 5)],
            incoming: [row("A", 3), row("B", 8)],
            metric: .memory, limit: 8)
        #expect(merged.map(\.name) == ["B", "A"])
        #expect(merged.map(\.value) == [8, 3])
    }

    @Test func testZeroRowsSettleAtTheBottom() {
        let merged = TopAppsService.mergedRows(
            previous: [row("A", 10), row("B", 5)],
            incoming: [row("A", 10)],
            metric: .memory, limit: 8)
        #expect(merged.map(\.name) == ["A", "B"])
        #expect(merged.last?.value == 0)
    }

    @Test func testLimitKeepsHighestValues() {
        let merged = TopAppsService.mergedRows(
            previous: [],
            incoming: [row("A", 10), row("B", 30), row("C", 20)],
            metric: .memory, limit: 2)
        #expect(merged.map(\.name) == ["B", "C"])
    }

    @Test func testLimitDropsZeroRowsBeforeLiveRows() {
        // B dropped to zero; a new live row C appears. With limit 2 the zero
        // row (not the live row) is evicted.
        let merged = TopAppsService.mergedRows(
            previous: [row("A", 10), row("B", 20)],
            incoming: [row("A", 10), row("C", 3)],
            metric: .memory, limit: 2)
        #expect(merged.map(\.name) == ["A", "C"])
    }

    @Test func testNetworkRanksByBusiestThenQuieterDirection() {
        // Rank by max(download, upload) first, then by the quieter direction.
        let downOnly = row("Down", 100, upload: 5)
        let upOnly = row("Up", 50, upload: 100)
        let quieter = row("Quieter", 90, upload: 20)
        let sorted = TopAppRanking.sorted([downOnly, upOnly, quieter], metric: .network)
        // Down and Up both peak at 100; Up's quieter direction (50) beats Down's (5).
        #expect(sorted.map(\.name) == ["Up", "Down", "Quieter"])
    }

    @Test func testEqualValuesKeepStableOrder() {
        let a = row("A", 10)
        let b = row("B", 10)
        let first = TopAppRanking.sorted([a, b], metric: .memory).map(\.name)
        let second = TopAppRanking.sorted([b, a], metric: .memory).map(\.name)
        #expect(first == second)
    }
}
