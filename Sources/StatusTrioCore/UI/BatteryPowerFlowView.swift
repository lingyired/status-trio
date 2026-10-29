import SwiftUI

/// A static flow diagram: sampling changes the numbers and ribbon widths, with
/// no animation clock, Canvas loop, or work while the panel is closed.
struct BatteryPowerFlowView: View {
    let state: BatteryPowerFlowState

    private var destinations: Int { (state.battery == nil ? 0 : 1) + (state.system == nil ? 0 : 1) }
    private var height: CGFloat { destinations > 1 ? 132 : 76 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let left: CGFloat = state.input == nil ? 0 : 66
            let right = width - 98
            let center = height / 2
            let batteryY: CGFloat = destinations > 1 ? 31 : center
            let systemY: CGFloat = destinations > 1 ? 101 : center
            let batteryFraction = state.batteryFlowFraction.map { CGFloat($0) }
            let systemFraction = state.systemFlowFraction.map { CGFloat($0) }
            if state.input != nil, destinations > 0 {
                if state.battery != nil {
                    ribbon(from: left, to: right, startY: center - (systemFraction ?? 0) * 23, endY: batteryY,
                        thickness: batteryFraction.map { $0 * 46 }, color: .green)
                }
                if state.system != nil {
                    ribbon(from: left, to: right, startY: center + (batteryFraction ?? 0) * 23, endY: systemY,
                        thickness: systemFraction.map { $0 * 46 }, color: .blue)
                }
            }
            if let input = state.input {
                metric(input, symbol: "powerplug.fill", color: .primary)
                    .frame(width: destinations == 0 ? width : 62, height: height - 8)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                    .position(x: destinations == 0 ? width / 2 : 31, y: center)
            }
            if let battery = state.battery {
                destination(battery, symbol: "battery.100.bolt", color: .green,
                    width: state.input == nil ? width : 94)
                    .position(x: state.input == nil ? width / 2 : width - 47, y: batteryY)
            }
            if let system = state.system {
                destination(system, symbol: "laptopcomputer", color: .blue,
                    width: state.input == nil ? width : 94)
                    .position(x: state.input == nil ? width / 2 : width - 47, y: systemY)
            }
        }
        .frame(height: height)
    }

    private func destination(_ value: BatteryPowerFlowState.Metric, symbol: String,
                             color: Color, width: CGFloat) -> some View {
        metric(value, symbol: symbol, color: color)
            .frame(width: width, height: 60)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ value: BatteryPowerFlowState.Metric, symbol: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(value.value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value.label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.label + ": " + value.value)
    }

    private func ribbon(from start: CGFloat, to end: CGFloat, startY: CGFloat,
                        endY: CGFloat, thickness: CGFloat?, color: Color) -> some View {
        let thickness = max(0, thickness ?? 0)
        return Path { path in
            let control = (end - start) * 0.5
            path.move(to: CGPoint(x: start, y: startY - thickness / 2))
            path.addCurve(to: CGPoint(x: end, y: endY - thickness / 2),
                control1: CGPoint(x: start + control, y: startY - thickness / 2),
                control2: CGPoint(x: end - control, y: endY - thickness / 2))
            path.addLine(to: CGPoint(x: end, y: endY + thickness / 2))
            path.addCurve(to: CGPoint(x: start, y: startY + thickness / 2),
                control1: CGPoint(x: end - control, y: endY + thickness / 2),
                control2: CGPoint(x: start + control, y: startY + thickness / 2))
            path.closeSubpath()
        }
        .fill(LinearGradient(colors: [color.opacity(0.08), color.opacity(0.3)],
            startPoint: .leading, endPoint: .trailing))
        .accessibilityHidden(true)
    }
}
