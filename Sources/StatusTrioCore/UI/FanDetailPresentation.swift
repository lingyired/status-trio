import Foundation

/// Pure fan-page presentation derived from one snapshot.
///
/// The page must not conflate three states:
/// - a fanless Mac (known count 0) → the fanless copy, never a fabricated card;
/// - a count that has not been read yet (`nil`) → unknown count and the
///   "unavailable" copy, never one placeholder fan;
/// - fans that exist but are not currently reporting → a card showing a dash.
struct FanDetailPresentation: Equatable {
    struct Row: Equatable {
        let index: Int
        let rpm: Double?
        let maxRPM: Double?
        let availability: HardwareMetricAvailability
        let sensorLabel: String?
    }

    /// Known fan controller count: `nil` until FNum is read, `0` when fanless.
    let fanCount: Int?
    let isFanless: Bool
    /// Average of the fans that currently report a value; includes stale values.
    let averageRPM: Double?
    let isAverageStale: Bool
    let rows: [Row]

    init(snapshot: HardwareMetricsSnapshot) {
        fanCount = snapshot.fanCount
        let average = snapshot.averageFanSample
        averageRPM = average.value
        isAverageStale = average.availability == .stale
        isFanless = average.availability == .unsupported && average.metadata.isFanless

        let count = max(snapshot.fanCount ?? 0, 0)
        rows = (0..<count).map { index in
            let sample = snapshot.samples[HardwareMetricID.fanRPM(index: index)]
            return Row(index: index,
                       rpm: sample?.value,
                       maxRPM: sample?.metadata.maximum,
                       availability: sample?.availability ?? .collecting,
                       sensorLabel: sample?.sensorLabel)
        }
    }
}
