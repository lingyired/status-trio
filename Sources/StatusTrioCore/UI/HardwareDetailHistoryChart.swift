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

    var body: some View {
        let maximum = yMaximum
        return VStack(spacing: 2) {
            ZStack(alignment: .topLeading) {
                HardwareDetailGrid()
                ForEach(colors.indices, id: \.self) { index in
                    HardwareDetailAreaShape(points: points, series: index, now: now, yMaximum: maximum)
                        .fill(LinearGradient(colors: [colors[index].opacity(0.78), colors[index].opacity(0.38)],
                                             startPoint: .top, endPoint: .bottom))
                    HardwareDetailLineShape(points: points, series: index, now: now, yMaximum: maximum)
                        .stroke(colors[index],
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    // Isolated samples would be invisible on a line path, so
                    // show them as small dots.
                    HardwareDetailChartDot(points: points, series: index, now: now,
                                           yMaximum: maximum, color: colors[index])
                }
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
        var visible: [(date: Date, value: Double)] = []
        for point in points {
            guard series < point.values.count, let value = point.values[series], value.isFinite else { continue }
            let elapsed = point.date.timeIntervalSince(start)
            guard elapsed >= 0, elapsed <= window else { continue }
            visible.append((point.date, value))
        }
        guard !visible.isEmpty else { return [] }
        // Map the samples actually present across the full width instead of
        // anchoring to the 60 s window. A freshly opened page (history shorter
        // than 60 s) no longer leaves a left gap, and a sample up to one refresh
        // interval behind `now` no longer leaves a right gap.
        let firstDate = visible[0].date
        let lastDate = visible[visible.count - 1].date
        let span = lastDate.timeIntervalSince(firstDate)
        // Fill edge to edge horizontally, but keep half a stroke of vertical
        // headroom so a 100% sample is not clipped by the plot boundary.
        let verticalInset: CGFloat = 0.75
        let usableHeight = max(0, size.height - verticalInset * 2)
        func y(for value: Double) -> CGFloat {
            verticalInset + usableHeight * CGFloat(1 - min(yMaximum, max(0, value)) / yMaximum)
        }
        // A single sample (page just opened, or only one point after an idle
        // gap) is drawn as a flat line across the full width so neither side
        // shows a gap while the next sample arrives.
        if visible.count == 1 {
            let item = visible[0]
            return [
                HardwareDetailChartSample(date: item.date, point: CGPoint(x: 0, y: y(for: item.value))),
                HardwareDetailChartSample(date: item.date, point: CGPoint(x: size.width, y: y(for: item.value)))
            ]
        }
        var result: [HardwareDetailChartSample] = []
        for item in visible {
            let ratio = span < 0.5 ? 0 : CGFloat(item.date.timeIntervalSince(firstDate) / span)
            let x = span < 0.5 ? size.width / 2 : size.width * ratio
            result.append(HardwareDetailChartSample(date: item.date, point: CGPoint(x: x, y: y(for: item.value))))
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

/// Filled area under the connected segments (gradient from the series colour),
/// matching the "solid" look while keeping the same time-axis geometry.
struct HardwareDetailAreaShape: Shape {
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
            guard let first = segment.first, let last = segment.last else { continue }
            // Close two points below the plot so the fill still meets the card
            // edge after clipping to the rounded card shape.
            path.move(to: CGPoint(x: first.x, y: rect.height + 2))
            path.addLine(to: first)
            for point in segment.dropFirst() { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: last.x, y: rect.height + 2))
            path.closeSubpath()
        }
        return path
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
