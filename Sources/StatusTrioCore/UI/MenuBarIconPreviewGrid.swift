import Foundation
import SwiftUI

/// Design preview: four menu-bar-style icons, one row, under System Monitoring.
/// Each icon uses a real metric for its arc and its short value/label, so the
/// size and density of a 4-up arrangement can be judged. The arc is drawn natively
/// so progress changes can animate instead of snapping between snapshots.
struct MenuBarIconPreviewGrid: View {
    @ObservedObject var hardware: HardwareMonitorObservable
    let colors: [HardwareMonitorMetric: IconRGBA]

    @State private var disk: DiskCapacitySample = .current()

    private var snapshot: HardwareMetricsSnapshot { hardware.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("菜单栏图标")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("实时 · 1 行 4 个")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(Self.items) { item in
                    let spec = spec(for: item)
                    PreviewRingIcon(
                        label: item.label,
                        center: spec.center,
                        progress: spec.progress,
                        color: IconAppearanceColorConversion.color(from: spec.color)
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                }
            }

            Text("图标约 60×60 pt · 标签在底部，数据实时")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("菜单栏图标预览，一行四个")
    }

    // MARK: - Items

    private enum Slot: String, CaseIterable, Identifiable {
        case cpu, gpu, ram, ssd
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }
    }

    private static let items = Slot.allCases

    private func spec(for slot: Slot) -> (center: String, progress: Double, color: IconRGBA) {
        switch slot {
        case .cpu:
            return ("\(temperatureText(.cpuTemperature))", percent(.cpuUsage), color(.cpuUsage))
        case .gpu:
            return ("\(temperatureText(.gpuTemperature))", percent(.gpuUsage), color(.gpuUsage))
        case .ram:
            return (memoryAvailableText, percent(.memoryUsage), color(.memoryUsage))
        case .ssd:
            return (disk.freeText, disk.usedFraction ?? 0,
                    IconRGBA(red: 0.55, green: 0.58, blue: 0.66, alpha: 1))
        }
    }

    // MARK: - Values

    private func color(_ metric: HardwareMonitorMetric) -> IconRGBA {
        colors[metric] ?? HardwareRingColorConfiguration.recommendedBaseColor(for: metric)
    }

    private func sample(_ id: HardwareMetricID) -> HardwareMetricSample? {
        snapshot.samples[id]
    }

    private func percent(_ id: HardwareMetricID) -> Double {
        guard let sample = sample(id), let value = sample.value, value.isFinite else { return 0 }
        return min(1, max(0, value / 100))
    }

    private func temperatureText(_ id: HardwareMetricID) -> String {
        guard let sample = sample(id), let value = sample.value, value.isFinite else { return "--" }
        return "\(Int(value.rounded()))°"
    }

    private var memoryAvailableText: String {
        guard let sample = sample(.memoryUsage), let usedPercent = sample.value, usedPercent.isFinite else { return "--" }
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let available = max(0, total * (1 - usedPercent / 100))
        return Self.compactBytes(available)
    }

    private static func compactBytes(_ bytes: Double) -> String {
        let gb = bytes / 1_000_000_000
        if gb >= 10 { return "\(Int(gb.rounded()))G" }
        return String(format: "%.1fG", gb)
    }
}

/// A natively drawn preview ring so progress changes can animate smoothly.
private struct PreviewRingIcon: View {
    let label: String
    let center: String
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let stroke = max(1.5, side * 0.055)
            ZStack {
                Circle()
                    .inset(by: side * 0.075)
                    .stroke(Color.secondary.opacity(0.22), lineWidth: stroke)
                Circle()
                    .inset(by: side * 0.075)
                    .trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.55), value: progress)
                centerText(side: side)
                Text(label)
                    .font(.system(size: side * 0.14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .offset(y: side * 0.30)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func centerText(side: CGFloat) -> some View {
        if center.count > 1, center.hasSuffix("°") {
            let number = String(center.dropLast())
            Text(number)
                .font(.system(size: side * 0.25, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .overlay(alignment: .topTrailing) {
                    Text("°")
                        .font(.system(size: side * 0.115, weight: .semibold))
                        .foregroundStyle(.primary)
                        .offset(x: side * 0.10, y: -side * 0.015)
                }
        } else {
            Text(center)
                .font(.system(size: side * 0.23, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}

/// Disk capacity for the SSD preview. `FileManager` volume keys are cheap enough
/// to read once when the preview appears; no polling is added.
struct DiskCapacitySample {
    let usedFraction: Double?
    let freeBytes: Int64?

    var freeText: String {
        guard let freeBytes else { return "--" }
        let gb = Double(freeBytes) / 1_000_000_000
        if gb >= 10 { return "\(Int(gb.rounded()))G" }
        return String(format: "%.1fG", gb)
    }

    static func current() -> DiskCapacitySample {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ])
        guard let total = values?.volumeTotalCapacity, total > 0 else {
            return DiskCapacitySample(usedFraction: nil, freeBytes: nil)
        }
        let free = values?.volumeAvailableCapacityForImportantUsage
        if let free {
            let used = max(0, min(1, 1 - Double(free) / Double(total)))
            return DiskCapacitySample(usedFraction: used, freeBytes: free)
        }
        return DiskCapacitySample(usedFraction: nil, freeBytes: nil)
    }
}
