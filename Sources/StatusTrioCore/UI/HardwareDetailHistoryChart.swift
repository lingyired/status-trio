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

    var body: some View {
        let maximum = yMaximum
        return VStack(spacing: 2) {
            ZStack {
                HardwareDetailGrid()
                ForEach(colors.indices, id: \.self) { index in
                    HardwareDetailLineShape(points: points, series: index, now: now, yMaximum: maximum)
                        .stroke(colors[index],
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: 54)
            HStack {
                Text(scale == .percent ? "0%" : "0")
                Spacer()
                Text(scale == .percent ? "100%" : HardwareDetailFormat.rateAxis(maximum))
            }
            .font(.system(size: 8))
            .foregroundStyle(.tertiary)
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
