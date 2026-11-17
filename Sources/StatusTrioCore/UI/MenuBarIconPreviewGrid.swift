import AppKit
import Foundation
import SwiftUI

/// The real four-ring strip (CPU, GPU, RAM, SSD) shared by the menu-bar design
/// preview and the status panel. It renders the app's actual ring scene and a
/// real metric per arc, so both surfaces stay pixel-identical.
struct HardwareRingStrip: View {
    @ObservedObject var hardware: HardwareMonitorObservable
    let colors: [HardwareMonitorMetric: IconRGBA]
    /// When true each ring is wrapped in its own glass card (status panel).
    var carded: Bool = false
    /// Opens the matching detail page when a carded ring is tapped. Nil keeps the
    /// cards non-interactive (design preview).
    var onSelectSlot: ((HardwareDetailKind) -> Void)? = nil
    /// Carded mode lifts the top percentage by this many points for optical
    /// centring inside the arc's top opening; other surfaces keep 0.
    static let cardedTopTextAdjustment: CGFloat = -3

    @State private var disk: DiskCapacitySample = .current()
    /// Pointer-enter glow so a clickable glass card reads as interactive
    /// (matches the keep-awake capsule in QuickActionsCardView).
    @State private var hoveredSlot: Slot?

    private var snapshot: HardwareMetricsSnapshot { hardware.snapshot }

    var body: some View {
        HStack(alignment: .top, spacing: carded ? 6 : 10) {
            ForEach(Slot.allCases) { slot in
                let spec = spec(for: slot)
                let ring = AnimatedSceneIcon(
                    label: slot.label,
                    top: spec.top,
                    center: spec.center,
                    centerScale: spec.centerScale,
                    color: spec.color,
                    progress: spec.progress,
                    topTextVerticalAdjustment: carded ? Self.cardedTopTextAdjustment : 0
                )
                .animation(.easeOut(duration: 0.55), value: spec.progress)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                if carded {
                    let card = ring
                        .padding(5)
                        .frame(maxWidth: .infinity)
                        .panelCardSurface(.silver(.connected), tint: .clear, cornerRadius: 13)
                    if let onSelectSlot {
                        Button { onSelectSlot(Self.detailKind(for: slot)) } label: {
                            card.contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.white.opacity(hoveredSlot == slot ? 0.06 : 0))
                                .allowsHitTesting(false)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.white.opacity(hoveredSlot == slot ? 0.22 : 0), lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                        .onHover { inside in
                            if inside { hoveredSlot = slot }
                            else if hoveredSlot == slot { hoveredSlot = nil }
                        }
                        .accessibilityLabel(slot.label)
                    } else {
                        card
                    }
                } else {
                    ring
                }
            }
        }
    }

    // MARK: - Slots

    private enum Slot: String, CaseIterable, Identifiable {
        case cpu, gpu, ram, ssd
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }
    }

    private static func detailKind(for slot: Slot) -> HardwareDetailKind {
        switch slot {
        case .cpu: return .cpu
        case .gpu: return .gpu
        case .ram: return .memory
        case .ssd: return .disk
        }
    }

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
                    HardwareRingColorConfiguration.solidStateDriveColor, fittedCenterScale(center, base: 0.8))
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

    private func fittedCenterScale(_ text: String, base: Double) -> Double {
        let count = text.count
        guard count > 4 else { return base }
        return max(0.52, base * 4.0 / Double(count))
    }

    private func percentText(_ id: HardwareMetricID?) -> String {
        if let id {
            return "\(Int((percent(id) * 100).rounded()))%"
        }
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

/// Design preview: the shared four-ring strip under System Monitoring, wrapped
/// with the explanatory title and footnote.
struct MenuBarIconPreviewGrid: View {
    @ObservedObject var hardware: HardwareMonitorObservable
    let colors: [HardwareMonitorMetric: IconRGBA]

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

            HardwareRingStrip(hardware: hardware, colors: colors)

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
struct AnimatedSceneIcon: View {
    let label: String
    let top: String
    let center: String
    let centerScale: Double
    let color: IconRGBA
    let progress: Double
    var topTextVerticalAdjustment: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                AnimatedRingLayer(color: color, progress: progress)
                    .animation(.easeOut(duration: 0.55), value: progress)
                Text(top)
                    .font(.system(size: side * 0.166 * 1.1, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .offset(y: -side * 0.33 + topTextVerticalAdjustment)
                centerValueText(side: side)
                Text(label)
                    .font(.system(size: side * 0.14, weight: .regular))
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
                .font(.system(size: fontSize, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .overlay(alignment: .topTrailing) {
                    Text("°")
                        .font(.system(size: fontSize * 0.5, weight: .regular))
                        .foregroundStyle(.primary)
                        .offset(x: fontSize * 0.35, y: -fontSize * 0.05)
                }
        } else {
            Text(center)
                .font(.system(size: fontSize, weight: .regular))
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
