import SwiftUI

/// Shared formatting for the five detail pages. Every unavailable value is an
/// em dash, never an invented zero.
enum HardwareDetailFormat {
    static let dash = "—"

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return dash }
        return "\(Int(min(100, max(0, value)).rounded()))%"
    }

    static func fractionPercent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return dash }
        return "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// Application CPU/GPU percentages may exceed 100% on multi-core machines,
    /// so they must not use the whole-machine 0–100 clamping above.
    static func appPercent(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return dash }
        return String(format: "%.1f%%", value)
    }

    static func temperature(_ value: Double?) -> String {
        guard let value, value.isFinite else { return dash }
        return "\(Int(value.rounded()))°C"
    }

    static func frequency(_ gigahertz: Double?) -> String {
        guard let gigahertz, gigahertz.isFinite, gigahertz > 0 else { return dash }
        return String(format: "%.2f GHz", gigahertz)
    }

    static func integer(_ value: Int?) -> String {
        guard let value else { return dash }
        return "\(value)"
    }

    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return dash }
        return bytes(Double(value))
    }

    static func bytes(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return dash }
        let gb = value / 1_000_000_000
        if gb >= 1000 { return String(format: "%.2f TB", gb / 1000) }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = value / 1_000_000
        return String(format: "%.0f MB", max(0, mb))
    }

    /// Bytes-per-second rate, picking a readable unit.
    static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return dash }
        if value >= 1_000_000_000 { return String(format: "%.2f GB/s", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1f MB/s", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0f KB/s", value / 1_000) }
        return String(format: "%.0f B/s", value)
    }

    /// Short max-label for the auto-scaled bandwidth chart.
    static func rateAxis(_ value: Double) -> String {
        rate(value).replacingOccurrences(of: "/s", with: "")
    }
}

/// One glass card shared by every detail page, so the five pages keep one
/// visual system and stay neutral-silver like the summary cards.
struct HardwareDetailCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelCardSurface(.silver(.connected), tint: .clear, cornerRadius: 13)
    }
}

/// A labelled value with an optional thin progress bar.
struct HardwareDetailMetricCard: View {
    let label: String
    let value: String
    var tertiary: String? = nil
    var progress: Double? = nil
    var progressTint: Color = .accentColor
    var valueSize: CGFloat = 20

    var body: some View {
        HardwareDetailCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(value)
                    .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let tertiary {
                    Text(tertiary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let progress {
                    HardwareDetailProgressBar(fraction: progress, tint: progressTint)
                }
            }
        }
    }
}

struct HardwareDetailProgressBar: View {
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

/// One CPU core class group shown on the CPU detail page.
struct HardwareCPUCoreGroup: Identifiable {
    let id: String
    let title: String
    let average: Double?
    let count: Int?
    let frequency: Double?
    let tint: Color
}

struct HardwareCPUCoreCard: View {
    let group: HardwareCPUCoreGroup
    let coresLabel: String
    let frequencyLabel: String
    var valueSize: CGFloat = 18

    var body: some View {
        HardwareDetailCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.title).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text("\(coresLabel) \(HardwareDetailFormat.integer(group.count))")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(HardwareDetailFormat.percent(group.average))
                    .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                HStack(spacing: 3) {
                    Text(frequencyLabel)
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(HardwareDetailFormat.frequency(group.frequency))
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                HardwareDetailProgressBar(fraction: (group.average ?? 0) / 100, tint: group.tint)
            }
        }
    }
}

/// Lays out one, two or three core groups without leaving an empty card.
struct HardwareCPUCoreGroupRow: View {
    let groups: [HardwareCPUCoreGroup]
    let coresLabel: String
    let frequencyLabel: String

    var body: some View {
        if groups.isEmpty {
            EmptyView()
        } else if groups.count == 1 {
            HardwareCPUCoreCard(group: groups[0], coresLabel: coresLabel,
                                frequencyLabel: frequencyLabel, valueSize: 20)
        } else {
            HStack(alignment: .top, spacing: groups.count >= 3 ? 5 : 8) {
                ForEach(groups) { group in
                    HardwareCPUCoreCard(group: group, coresLabel: coresLabel,
                                        frequencyLabel: frequencyLabel,
                                        valueSize: groups.count >= 3 ? 15 : 18)
                }
            }
        }
    }
}

/// A label/value row used by the detail sections.
struct HardwareDetailRow: View {
    let label: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(valueColor ?? Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}
