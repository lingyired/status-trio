import SwiftUI

/// A static flow diagram: sampling changes the numbers and ribbon widths, with
/// no animation clock, Canvas loop, or work while the panel is closed.
struct BatteryPowerFlowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let state: BatteryPowerFlowState

    private var destinations: [BatteryPowerFlowState.Metric] { state.destinations }
    /// Extra breathing room above and below the branch column.
    private let topPadding: CGFloat = 2

    /// Rows grow with the branch's share of the budget so the card column reads
    /// in the same proportion as the ribbons: a minimum one-line row, a maximum
    /// two-line row, linear in between. A row that reaches the label height
    /// shows the branch name; shorter rows only fit "icon + watts".
    private static let minRow: CGFloat = 16
    private static let maxRow: CGFloat = 80
    private static let labelRow: CGFloat = 34
    /// Rows at or below this height are too small for the normal type scale;
    /// their icon, number and padding shrink so a 2-4% branch stays readable
    /// without looking as heavy as a large one.
    private static let denseRow: CGFloat = 22
    private static let rowGap: CGFloat = 6
    /// The input card holds one number and its label, so it stays a small node;
    /// the branch column is allowed to grow taller than it.
    private static let inputCardHeight: CGFloat = 84
    /// The ribbon bundle is centred in the input card with a 5% margin above
    /// and below, so it reads as one stream leaving the middle of the card.
    private static let bundleInset: CGFloat = 0.05
    /// The panel chrome is transparent Liquid Glass, so the previous very light
    /// fills (0.045–0.08) vanished over a bright or colourful desktop. These
    /// fills and rims keep each node and ribbon legible without hiding the glass.
    /// The input chip shares the outer power bar's styling through
    /// `PowerCardSurface` (silver fill and rim, radius 12), so the two "charger
    /// input" cards read the same in both appearances.
    private static let cardFill: Double = 0.18
    private static let cardStroke: Double = 0.32
    private static let ribbonFillStart: Double = 0.22
    private static let ribbonFillEnd: Double = 0.62

    /// Every branch's height is its share of the budget, for any number of
    /// branches. The proportion is itself a reading: a 0.3% display branch must
    /// not look as heavy as the system load beside it.
    private func rowHeight(_ index: Int) -> CGFloat {
        let share = min(1, max(0, state.flowFraction(for: destinations[index]) ?? 0))
        return Self.minRow + (Self.maxRow - Self.minRow) * share
    }

    private func showsLabel(_ index: Int) -> Bool {
        rowHeight(index) >= Self.labelRow
    }

    /// Height of the branch column itself, without the view's padding.
    private var columnHeight: CGFloat {
        guard !destinations.isEmpty else { return 0 }
        return destinations.indices.reduce(CGFloat.zero) { $0 + rowHeight($1) }
            + Self.rowGap * CGFloat(destinations.count - 1)
    }

    private var height: CGFloat {
        switch destinations.count {
        case 0, 1: return Self.inputCardHeight
        default: return topPadding * 2 + max(Self.inputCardHeight, columnHeight)
        }
    }

    private func centerY(_ index: Int) -> CGFloat {
        let rows = destinations.indices.reduce(0) { $0 + rowHeight($1) }
        let column = rows + Self.rowGap * CGFloat(destinations.count - 1)
        // A short column sits centred against the taller input card.
        var top = topPadding + max(0, (Self.inputCardHeight - column) / 2)
        for row in 0..<index { top += rowHeight(row) + Self.rowGap }
        return top + rowHeight(index) / 2
    }

    private struct Ribbon: Identifiable {
        let id: Int
        let startY: CGFloat
        let endY: CGFloat
        let thickness: CGFloat
        let endThickness: CGFloat
        let color: Color
    }

    /// Ribbons leave the input card as one bundle that fills it, so the left
    /// edge reads as a single stream. Every branch that carries power gets a
    /// minimum width and the rest of the bundle is shared by the branches'
    /// percentages; a band that would cross into a neighbour is trimmed and the
    /// trimmed height goes to the bands that still have room.
    private func ribbons() -> [Ribbon] {
        let count = destinations.count
        guard count > 0 else { return [] }
        let fractions = destinations.map {
            max(0, state.flowFraction(for: $0).map { CGFloat($0) } ?? 0)
        }
        let total = fractions.reduce(0, +)
        let bundleHeight = Self.inputCardHeight * (1 - 2 * Self.bundleInset)
        let top = height / 2 - bundleHeight / 2
        let live = destinations.indices.filter { fractions[$0] > 0 }
        guard total > 0 else { return [] }
        let minimum = min(CGFloat(6), bundleHeight / CGFloat(live.count))
        var thicknesses = Array(repeating: CGFloat.zero, count: count)
        var remaining = bundleHeight
        var pending = live
        // Apply the lower bound only to small shares; preserve proportional
        // allocation among all branches that remain above it.
        while !pending.isEmpty {
            let weight = pending.reduce(CGFloat.zero) { $0 + fractions[$1] }
            let small = pending.filter { remaining * fractions[$0] / weight < minimum }
            if small.isEmpty {
                for index in pending { thicknesses[index] = remaining * fractions[index] / weight }
                break
            }
            for index in small { thicknesses[index] = minimum; remaining -= minimum }
            pending.removeAll { small.contains($0) }
        }
        var offset = top
        return live.map { index in
            let thickness = thicknesses[index]
            let startY = offset + thickness / 2
            offset += thickness
            // The source keeps the branch's full share; only the end is tapered
            // to fit its card, so a dominant branch does not shrink the others.
            let endThickness = min(thickness, max(0, rowHeight(index) - 8))
            return Ribbon(id: index, startY: startY, endY: centerY(index),
                          thickness: thickness, endThickness: endThickness,
                          color: Self.color(for: destinations[index].kind))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // The input card is 62 wide and centred at x=31; each branch card
            // is 94 wide at the right edge. Ribbons continue underneath their
            // original rounded outlines; the mask below cuts out card interiors
            // so the overlap cannot show through their translucent fills.
            let left: CGFloat = state.input == nil
                ? 0
                : PowerFlowCardGeometry.ribbonStartX(inputCardRight: 62)
            let right = PowerFlowCardGeometry.ribbonEndX(branchCardLeft: width - 94)
            let center = height / 2
            // A ribbon at or below the drawing floor is not drawn.
            let liveRibbons = (state.input != nil && !destinations.isEmpty)
                ? ribbons().filter { $0.thickness > PowerFlowCardGeometry.liveThreshold }
                : []
            // Mask the ribbon layer with the exact card silhouettes. Drawing
            // the translucent cards above it is not enough to hide the overlap.
            let inputFrame = CGRect(x: 0, y: center - Self.inputCardHeight / 2,
                                    width: 62, height: Self.inputCardHeight)
            let branchFrames = destinations.indices.map { index in
                CGRect(x: width - 94, y: centerY(index) - rowHeight(index) / 2,
                       width: 94, height: rowHeight(index))
            }
            ZStack {
                ForEach(liveRibbons) { item in
                    ribbon(from: left, to: right, startY: item.startY, endY: item.endY,
                           thickness: item.thickness, endThickness: item.endThickness, color: item.color)
                }
            }
            .frame(width: width, height: height)
            .mask {
                PowerFlowRibbonMask(cardFrames: [inputFrame] + branchFrames)
                    .fill(style: FillStyle(eoFill: true))
            }
            if let input = state.input {
                // The source node is the adapter (plug, primary) unless the pack
                // is discharging, in which case it takes the outer bar's
                // discharging card style (plain battery, orange).
                let inputColor = Self.color(for: input.kind)
                let inputSurface = Self.surface(for: input.kind)
                metric(input, symbol: Self.symbol(for: input.kind), color: inputColor,
                       height: Self.inputCardHeight, singleLine: false,
                       iconSize: Self.iconSize(for: input.kind),
                       iconLeading: false)
                    .frame(width: destinations.isEmpty ? width : 62)
                    // `Self.color(for:)` returns the explicit `.primary` colour,
                    // not a bare `.primary` shape style: the leading-dot form
                    // resolves to the hierarchical foreground, follows the vibrant
                    // detail-page text and nearly vanishes over the glass.
                    .powerFlowCardSurface(
                        fill: inputSurface.fill(tint: inputColor, scheme: colorScheme),
                        stroke: inputSurface.stroke(tint: inputColor, scheme: colorScheme)
                    )
                    .position(x: destinations.isEmpty ? width / 2 : 31, y: center)
            }
            ForEach(Array(destinations.enumerated()), id: \.offset) { index, item in
                metric(item, symbol: Self.symbol(for: item.kind),
                       color: Self.color(for: item.kind), height: rowHeight(index),
                       singleLine: !showsLabel(index),
                       dense: !showsLabel(index) && rowHeight(index) <= Self.denseRow,
                       iconSize: !showsLabel(index) && rowHeight(index) <= Self.denseRow
                           ? 10 : Self.iconSize(for: item.kind))
                    .frame(width: state.input == nil ? width : 94)
                    .powerFlowCardSurface(
                        fill: Self.color(for: item.kind).opacity(Self.cardFill),
                        stroke: Self.color(for: item.kind).opacity(Self.cardStroke)
                    )
                    .position(x: state.input == nil ? width / 2 : width - 47, y: centerY(index))
            }
        }
        .frame(height: height)
    }

    private static func symbol(for kind: BatteryPowerFlowState.Kind) -> String {
        switch kind {
        case .input: return "powerplug.fill"
        // The pack as the source: plain battery, matching the outer bar's
        // discharging card (only charging carries the bolt).
        case .batterySource: return "battery.100"
        case .charging: return "battery.100.bolt"
        case .display: return "display"
        case .usb: return "cable.connector"
        case .system: return "cpu"
        }
    }

    private static func color(for kind: BatteryPowerFlowState.Kind) -> Color {
        switch kind {
        case .input: return .primary
        // Same orange as the outer power bar's discharging battery card.
        case .batterySource: return .orange
        case .charging: return .green
        case .display: return .indigo
        case .usb: return .orange
        case .system: return .blue
        }
    }

    /// The input card's surface: the shared silver while the adapter supplies
    /// power, and the input-card tint wash (not the branch cards' slightly
    /// heavier rim) when the pack is the source instead.
    static func surface(for kind: BatteryPowerFlowState.Kind) -> PowerCardSurface {
        switch kind {
        case .input: return .silver(.connected)
        case .batterySource, .charging, .display, .usb, .system:
            return .tint(fillOpacity: 0.18, strokeOpacity: 0.3)
        }
    }

    /// SF Symbols do not share one optical weight: the battery glyph reads
    /// larger than the display and connector glyphs at the same point size.
    private static func iconSize(for kind: BatteryPowerFlowState.Kind) -> CGFloat {
        switch kind {
        case .input: return 15
        case .batterySource: return 13
        case .charging: return 12
        case .display, .usb, .system: return 13
        }
    }

    private func metric(_ value: BatteryPowerFlowState.Metric, symbol: String,
                        color: Color, height: CGFloat, singleLine: Bool,
                        dense: Bool = false, iconSize: CGFloat = 14,
                        iconLeading: Bool = true) -> some View {
        Group {
            if iconLeading {
            // Icon and number share the first row (so the icon reads as part of
            // that number, not as a separate column) and the branch name sits
            // underneath, centred. The icon column is fixed so every card puts
            // its icon on the same vertical line.
            if singleLine {
                HStack(spacing: dense ? 4 : 6) {
                    Image(systemName: symbol)
                        .foregroundStyle(color)
                        .font(.system(size: iconSize, weight: .medium))
                        // Keep the icon column fixed so every row lines its
                        // icon up, even when the glyph itself is smaller.
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(value.value)
                        .font(.system(size: dense ? 10 : 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 1) {
                    HStack(spacing: 6) {
                        Image(systemName: symbol)
                            .foregroundStyle(color)
                            .font(.system(size: iconSize, weight: .medium))
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(value.value)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(value.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            } else {
                // The narrow input card keeps its icon above the number.
                VStack(spacing: 3) {
                    Image(systemName: symbol)
                        .foregroundStyle(color)
                        .font(.system(size: 16, weight: .medium))
                        .accessibilityHidden(true)
                    Text(value.value)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(value.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((value.help ?? value.label) + ": " + value.value)
        .help(value.help ?? value.label)
    }

    private func ribbon(from start: CGFloat, to end: CGFloat, startY: CGFloat,
                        endY: CGFloat, thickness: CGFloat?, endThickness: CGFloat, color: Color) -> some View {
        let thickness = max(0, thickness ?? 0)
        return Path { path in
            let control = (end - start) * 0.5
            path.move(to: CGPoint(x: start, y: startY - thickness / 2))
            path.addCurve(to: CGPoint(x: end, y: endY - endThickness / 2),
                control1: CGPoint(x: start + control, y: startY - thickness / 2),
                control2: CGPoint(x: end - control, y: endY - endThickness / 2))
            path.addLine(to: CGPoint(x: end, y: endY + endThickness / 2))
            path.addCurve(to: CGPoint(x: start, y: startY + thickness / 2),
                control1: CGPoint(x: end - control, y: endY + endThickness / 2),
                control2: CGPoint(x: start + control, y: startY + thickness / 2))
            path.closeSubpath()
        }
        .fill(LinearGradient(colors: [color.opacity(Self.ribbonFillStart), color.opacity(Self.ribbonFillEnd)],
            startPoint: .leading, endPoint: .trailing))
        .accessibilityHidden(true)
    }
}
