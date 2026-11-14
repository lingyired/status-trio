import AppKit
import Foundation
import SwiftUI

/// Design preview: four menu-bar icons, one row, under System Monitoring. Each
/// icon uses the app's real ring renderer (same scene/renderer as the menu bar)
/// and a real metric for its arc, so the size and density of a 4-up arrangement
/// can be judged. Progress changes are interpolated with the app's scene so the
/// arc animates instead of snapping.
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

            HStack(alignment: .top, spacing: 10) {
                ForEach(Self.items) { item in
                    let spec = spec(for: item)
                    AnimatedSceneIcon(
                        label: item.label,
                        top: spec.top,
                        center: spec.center,
                        centerScale: spec.centerScale,
                        color: spec.color,
                        progress: spec.progress
                    )
                    .animation(.easeOut(duration: 0.55), value: spec.progress)
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

    private func spec(for slot: Slot) -> (top: String, center: String, progress: Double, color: IconRGBA, centerScale: Double) {
        switch slot {
        case .cpu:
            let center = temperatureText(.cpuTemperature)
            return (percentText(.cpuUsage), center, percent(.cpuUsage), color(.cpuUsage), fittedCenterScale(center, base: 1.05))
        case .gpu:
            let center = temperatureText(.gpuTemperature)
            return (percentText(.gpuUsage), center, percent(.gpuUsage), color(.gpuUsage), fittedCenterScale(center, base: 1.05))
        case .ram:
            let center = memoryAvailableText
            return (percentText(.memoryUsage), center, percent(.memoryUsage), color(.memoryUsage), fittedCenterScale(center, base: 0.8))
        case .ssd:
            let center = disk.freeText
            return (percentText(nil), center, disk.usedFraction ?? 0,
                    IconRGBA(red: 0.55, green: 0.58, blue: 0.66, alpha: 1), fittedCenterScale(center, base: 0.8))
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

    /// Capacity strings such as "1000G" are wider than the centre slot; shrink
    /// the font once the text grows past four characters.
    private func fittedCenterScale(_ text: String, base: Double) -> Double {
        let count = text.count
        guard count > 4 else { return base }
        return max(0.52, base * 4.0 / Double(count))
    }

    private func percentText(_ id: HardwareMetricID?) -> String {
        if let id {
            return "\(Int((percent(id) * 100).rounded()))%"
        }
        // SSD has no hardware sample; use its disk fraction.
        return "\(Int(((disk.usedFraction ?? 0) * 100).rounded()))%"
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
        if gb >= 10 { return "\(Int(gb.rounded()))GB" }
        return String(format: "%.1fGB", gb)
    }
}

/// Renders only the app's real ring (no text) and lets the caller overlay static
/// text. Conforming to `Animatable` means only the ring's progress interpolates;
/// numeric/label text changes are siblings and update instantly.
private struct AnimatedRingLayer: View, Animatable {
    let color: IconRGBA
    var progress: Double

    @Environment(\.colorScheme) private var colorScheme

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var image: NSImage? {
        let ring = OuterRingState(
            segments: [RingSegmentState(progress: progress, color: .custom(color))],
            gap: .value,
            layout: .standard,
            accessory: nil,
            strokeScale: 1.1
        )
        return StatusIconPreviewCache.shared.image(
            scene: IconSceneState(outerRing: ring, center: nil),
            size: 72,
            scale: 2,
            appearance: MenuBarPreviewBackdrop.appearance(isDarkBackground: colorScheme == .dark)
        )
    }
}

/// Static text layer over the animated app ring: top percentage, centre value
/// and bottom label. These never animate with the ring progress.
private struct AnimatedSceneIcon: View {
    let label: String
    let top: String
    let center: String
    let centerScale: Double
    let color: IconRGBA
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                AnimatedRingLayer(color: color, progress: progress)
                    .animation(.easeOut(duration: 0.55), value: progress)
                Text(top)
                    .font(.system(size: side * 0.166 * 1.1, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .offset(y: -side * 0.33)
                centerValueText(side: side)
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
    private func centerValueText(side: CGFloat) -> some View {
        let fontSize = side * 0.285 * centerScale
        if center.count > 1, center.hasSuffix("°") {
            let number = String(center.dropLast())
            Text(number)
                .font(.system(size: fontSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .overlay(alignment: .topTrailing) {
                    Text("°")
                        .font(.system(size: fontSize * 0.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .offset(x: fontSize * 0.35, y: -fontSize * 0.05)
                }
        } else {
            Text(center)
                .font(.system(size: fontSize, weight: .semibold))
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
        if gb >= 10 { return "\(Int(gb.rounded()))GB" }
        return String(format: "%.1fGB", gb)
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
