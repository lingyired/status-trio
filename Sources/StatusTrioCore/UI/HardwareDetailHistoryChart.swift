import SwiftUI

enum HardwareDetailChartScale {
    case percent
    case auto
}

/// Lightweight 60 s line chart (single or dual series) using a plain SwiftUI
/// Shape — no Canvas TimelineView, no continuous redraw. Missing values break the
/// curve instead of drawing zero; a genuine pause breaks it, while a uniformly
/// slow sampling cadence still draws a continuous line.
struct HardwareDetailHistoryChart: View {
    let points: [HardwareDetailHistoryPoint]
    let colors: [Color]
    var scale: HardwareDetailChartScale = .percent
    let now: Date

    private var yMaximum: Double {
        switch scale {
        case .percent:
            return 100
        case .auto:
            let maxValue = points
                .flatMap { $0.values }
                .compactMap { $0 }
                .max() ?? 0
            return max(1, maxValue * 1.15)
        }
    }

    private var maximumLabel: String {
        scale == .percent ? "100%" : HardwareDetailFormat.rateAxis(yMaximum)
    }

    private var minimumLabel: String {
        scale == .percent ? "0%" : "0"
    }

    var body: some View {
        let maximum = yMaximum
        return VStack(spacing: 2) {
            ZStack(alignment: .topLeading) {
                HardwareDetailGrid()
                ForEach(colors.indices, id: \.self) { index in
                    HardwareDetailLineShape(points: points, series: index, now: now, yMaximum: maximum)
                        .stroke(colors[index],
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    // Isolated samples would be invisible on a line path, so
                    // show them as small dots.
                    HardwareDetailChartDot(points: points, series: index, now: now,
                                           yMaximum: maximum, color: colors[index])
                }
                // Value-axis labels sit on the left edge.
                VStack(alignment: .leading) {
                    Text(maximumLabel)
                    Spacer(minLength: 0)
                    Text(minimumLabel)
                }
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .padding(.leading, 2)
                .padding(.vertical, 1)
                .allowsHitTesting(false)
            }
            .frame(height: 54)
        }
    }
}

/// One visible sample converted to a point in the plot.
struct HardwareDetailChartSample {
    let date: Date
    let point: CGPoint
}

/// Shared geometry for the line and the isolated-point dots.
enum HardwareDetailChartGeometry {
    static func samples(points: [HardwareDetailHistoryPoint], series: Int,
                        now: Date, yMaximum: Double, size: CGSize) -> [HardwareDetailChartSample] {
        guard size.width > 0, size.height > 0, yMaximum > 0 else { return [] }
        let window = HardwareDetailHistoryStore.window
        let start = now.addingTimeInterval(-window)
        var result: [HardwareDetailChartSample] = []
        for point in points {
            guard series < point.values.count, let value = point.values[series], value.isFinite else { continue }
            let elapsed = point.date.timeIntervalSince(start)
            guard elapsed >= 0, elapsed <= window else { continue }
            let x = size.width * CGFloat(elapsed / window)
            let y = size.height * CGFloat(1 - min(yMaximum, max(0, value)) / yMaximum)
            result.append(HardwareDetailChartSample(date: point.date, point: CGPoint(x: x, y: y)))
        }
        return result
    }

    /// The chart window is 60 s, so any two visible samples are at most 60 s
    /// apart. Keep the curve continuous across normal cadence changes (1 s ↔ 15 s
    /// ↔ 60 s) instead of turning slow samples into isolated dots; a lone sample
    /// is still drawn as a dot. Gaps larger than the window simply contain no
    /// points, so nothing is fabricated.
    static func breakThreshold(for samples: [HardwareDetailChartSample]) -> TimeInterval {
        HardwareDetailHistoryStore.window
    }

    static func segments(for samples: [HardwareDetailChartSample],
                         threshold: TimeInterval) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []
        var previousDate: Date?
        for sample in samples {
            if let previousDate, sample.date.timeIntervalSince(previousDate) > threshold {
                if !current.isEmpty { result.append(current); current = [] }
            }
            current.append(sample.point)
            previousDate = sample.date
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Points with no neighbour within the break threshold are drawn as dots so
    /// sparse or genuinely gapped samples stay visible.
    static func isolatedPoints(for samples: [HardwareDetailChartSample],
                               threshold: TimeInterval) -> [CGPoint] {
        guard !samples.isEmpty else { return [] }
        if samples.count == 1 { return [samples[0].point] }
        var result: [CGPoint] = []
        for index in samples.indices {
            let previousGap = index > 0
                ? samples[index].date.timeIntervalSince(samples[index - 1].date) : .infinity
            let nextGap = index < samples.count - 1
                ? samples[index + 1].date.timeIntervalSince(samples[index].date) : .infinity
            if previousGap > threshold && nextGap > threshold {
                result.append(samples[index].point)
            }
        }
        return result
    }
}

/// Draws the isolated samples of one series as small dots.
struct HardwareDetailChartDot: View {
    let points: [HardwareDetailHistoryPoint]
    let series: Int
    let now: Date
    let yMaximum: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let samples = HardwareDetailChartGeometry.samples(points: points, series: series,
                                                              now: now, yMaximum: yMaximum,
                                                              size: geometry.size)
            let threshold = HardwareDetailChartGeometry.breakThreshold(for: samples)
            let dots = HardwareDetailChartGeometry.isolatedPoints(for: samples, threshold: threshold)
            ForEach(Array(dots.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(color)
                    .frame(width: 3, height: 3)
                    .position(point)
            }
        }
    }
}

/// Faint 25 / 50 / 75 % guides.
struct HardwareDetailGrid: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for step in 1..<4 {
                    let y = geometry.size.height * CGFloat(step) / 4
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }
}

struct HardwareDetailLineShape: Shape {
    let points: [HardwareDetailHistoryPoint]
    let series: Int
    let now: Date
    let yMaximum: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let samples = HardwareDetailChartGeometry.samples(points: points, series: series,
                                                          now: now, yMaximum: yMaximum,
                                                          size: rect.size)
        let threshold = HardwareDetailChartGeometry.breakThreshold(for: samples)
        for segment in HardwareDetailChartGeometry.segments(for: samples, threshold: threshold)
        where segment.count > 1 {
            path.move(to: segment[0])
            for point in segment.dropFirst() { path.addLine(to: point) }
        }
        return path
    }
}
