import SwiftUI

enum HardwareDetailChartScale {
    case percent
    case auto
}

/// Lightweight 60 s line chart (single or dual series) using a plain SwiftUI
/// Shape — no Canvas TimelineView, no continuous redraw. Missing values and gaps
/// longer than the store's threshold break the curve instead of drawing zero.
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
                    // A single background sample drawn as a line would be
                    // invisible (path has only a move), so show it as a dot.
                    HardwareDetailChartDot(points: points, series: index, now: now,
                                           yMaximum: maximum, color: colors[index])
                }
                // Vertical (value) axis labels sit on the left edge, so the
                // bottom row can describe time instead of repeating 0/100.
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
            HStack {
                Text("-60s")
                Spacer()
                Text("0s")
            }
            .font(.system(size: 8))
            .foregroundStyle(.tertiary)
        }
    }
}

/// Draws one dot when a series has exactly one visible sample.
struct HardwareDetailChartDot: View {
    let points: [HardwareDetailHistoryPoint]
    let series: Int
    let now: Date
    let yMaximum: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let coordinates = visibleCoordinates(size: geometry.size)
            if coordinates.count == 1, let point = coordinates.first {
                Circle()
                    .fill(color)
                    .frame(width: 3, height: 3)
                    .position(point)
            }
        }
    }

    private func visibleCoordinates(size: CGSize) -> [CGPoint] {
        guard size.width > 0, size.height > 0, yMaximum > 0 else { return [] }
        let window = HardwareDetailHistoryStore.window
        let start = now.addingTimeInterval(-window)
        var result: [CGPoint] = []
        for point in points {
            guard series < point.values.count, let value = point.values[series], value.isFinite else { continue }
            let elapsed = point.date.timeIntervalSince(start)
            guard elapsed >= 0, elapsed <= window else { continue }
            let x = size.width * CGFloat(elapsed / window)
            let y = size.height * CGFloat(1 - min(yMaximum, max(0, value)) / yMaximum)
            result.append(CGPoint(x: x, y: y))
        }
        return result
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
        guard rect.width > 0, rect.height > 0, yMaximum > 0, !points.isEmpty else { return path }
        let window = HardwareDetailHistoryStore.window
        let start = now.addingTimeInterval(-window)
        var previous: (point: CGPoint, date: Date)?
        for point in points {
            guard series < point.values.count, let value = point.values[series], value.isFinite else {
                previous = nil
                continue
            }
            let elapsed = point.date.timeIntervalSince(start)
            guard elapsed >= 0, elapsed <= window else { continue }
            let clamped = min(yMaximum, max(0, value))
            let x = rect.width * CGFloat(elapsed / window)
            let y = rect.height * CGFloat(1 - clamped / yMaximum)
            let current = CGPoint(x: x, y: y)
            if let previous, point.date.timeIntervalSince(previous.date) <= HardwareDetailHistoryStore.maximumGap {
                path.addLine(to: current)
            } else {
                path.move(to: current)
            }
            previous = (current, point.date)
        }
        return path
    }
}
