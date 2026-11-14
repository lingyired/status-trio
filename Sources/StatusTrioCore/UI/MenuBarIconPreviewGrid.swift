import AppKit
import SwiftUI

/// Design preview: four menu-bar-style icons, one row, under System Monitoring.
/// Each icon uses a real metric for its arc and its label/short value for the top
/// and centre, so the size and density of a 4-up arrangement can be judged.
struct MenuBarIconPreviewGrid: View {
    @ObservedObject var hardware: HardwareMonitorObservable
    let colors: [HardwareMonitorMetric: IconRGBA]

    @Environment(\.colorScheme) private var colorScheme
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

            HStack(spacing: 10) {
                ForEach(Self.items) { item in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if let image = image(for: item) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                            }
                        }
                }
            }

            Text("图标约 60×60 pt（面板宽 330 时）· 圆弧/数值均取当前实时数据")
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

    private func image(for slot: Slot) -> NSImage? {
        StatusIconPreviewCache.shared.image(
            scene: scene(for: slot),
            size: 72,
            scale: 2,
            appearance: MenuBarPreviewBackdrop.appearance(isDarkBackground: colorScheme == .dark)
        )
    }

    private func scene(for slot: Slot) -> IconSceneState {
        let spec: (center: String, progress: Double, color: IconRGBA, topScale: Double, centerScale: Double)
        switch slot {
        case .cpu:
            spec = ("\(temperatureText(.cpuTemperature))", percent(.cpuUsage),
                    color(.cpuUsage), 1.05, 1.05)
        case .gpu:
            spec = ("\(temperatureText(.gpuTemperature))", percent(.gpuUsage),
                    color(.gpuUsage), 1.05, 1.05)
        case .ram:
            spec = (memoryAvailableText, percent(.memoryUsage),
                    color(.memoryUsage), 0.95, 0.8)
        case .ssd:
            spec = (disk.freeText, disk.usedFraction ?? 0,
                    IconRGBA(red: 0.55, green: 0.58, blue: 0.66, alpha: 1), 0.95, 0.8)
        }
        let ring = OuterRingState(
            segments: [RingSegmentState(progress: spec.progress, color: .custom(spec.color))],
            gap: .value,
            layout: .standard,
            accessory: .text(IconTextState(text: slot.label, color: .primary, scale: spec.topScale)),
            strokeScale: 1.1
        )
        return IconSceneState(
            outerRing: ring,
            center: .text(IconTextState(text: spec.center, color: .primary, scale: spec.centerScale))
        )
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
