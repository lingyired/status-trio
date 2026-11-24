import AppKit
import Foundation
import SwiftUI

/// The real four-ring strip (CPU, GPU, RAM, SSD) shared by the menu-bar design
/// preview and the status panel. It renders the app's actual ring scene and a
/// real metric per arc, so both surfaces stay pixel-identical.
struct HardwareRingStrip: View {
    @ObservedObject var hardware: HardwareMonitorObservable
    let colors: [HardwareMonitorMetric: IconRGBA]
    /// Colour of the SSD ring arc. SSD usage comes from the disk-capacity query,
    /// not a sampled metric, so it is passed here instead of in `colors`.
    var diskColor: IconRGBA = HardwareRingColorConfiguration.solidStateDriveColor
    /// When true each ring is wrapped in its own glass card (status panel).
    var carded: Bool = false
    /// Opens the matching detail page when a carded ring is tapped. Nil keeps the
    /// cards non-interactive (design preview).
    var onSelectSlot: ((HardwareDetailKind) -> Void)? = nil
    /// Which rings to draw, in order. In carded mode the visible cards share the
    /// full width in equal columns, so two take half each and three take a third
    /// each. Card height and ring diameter stay fixed as in the four-up layout;
    /// the ring is centred inside its (wider) card.
    var visibleSlots: [HardwareRingSlot] = HardwareRingSlot.allCases
    /// Carded mode lifts the top percentage by this many points for optical
    /// centring inside the arc's top opening; other surfaces keep 0.
    static let cardedTopTextAdjustment: CGFloat = -3
    /// When false the live rings snap to each sample instead of tweening. The
    /// status panel refreshes as often as every second, and a 0.55 s tween per
    /// update kept the display link busy almost continuously on Debug builds.
    var animatesProgress: Bool = true
    /// Ring value semantics for RAM and SSD; CPU/GPU are always consumed.
    var memoryDisplayMode: RingValueDisplayMode = .used
    var ssdDisplayMode: RingValueDisplayMode = .used
    /// What the CPU/GPU ring draws in its center. GPU only supports temperature
    /// today; when monitoring is off both rings drop the temperature reading.
    var cpuCenterContent: HardwareRingCenterContent = .temperature
    var gpuCenterContent: HardwareRingCenterContent = .temperature
    var temperatureMonitoringEnabled: Bool = true
    /// Whether each ring's progress is split across the top gap (left half
    /// 0–50%, right half 50–100%) instead of the gap absorbing it (#375).
    var splitGapProgress: Bool = false
    /// Whether the SSD ring's top percentage pools selected external volumes
    /// with the internal disk. Only the carded (status panel) SSD card shows the
    /// external total footer; the menu-bar strip stays internal-only.
    var ssdIncludeExternalInPercent: Bool = false
    /// Mount paths of external volumes the user ticked to include in the total.
    var ssdSelectedExternalPaths: Set<String> = []

    /// Capacity is read once when the strip appears, not on every redraw: the
    /// volume query is a real filesystem/APFS lookup and was running on every
    /// parent body evaluation because a `@State` default expression is still
    /// evaluated each time the view struct is created.
    @State private var disk: DiskCapacitySample = .empty
    /// External volumes, read once alongside the internal capacity so the SSD
    /// card can show the selected external total without per-frame filesystem
    /// work.
    @State private var externalVolumes: [DiskVolumeReading] = []
    /// Pointer-enter glow so a clickable glass card reads as interactive
    /// (matches the keep-awake capsule in QuickActionsCardView).
    @State private var hoveredSlot: HardwareRingSlot?
    /// Card strategy and appearance, so the solid branch can substitute the
    /// neutral hardware hover / rim instead of the glass white overlay.
    @Environment(\.panelCardSurfaceStyle) private var panelCardStyle

    private var snapshot: HardwareMetricsSnapshot { hardware.snapshot }

    var body: some View {
        Group {
            if carded {
                // Keep a fixed four-column card width; the visible cards centre and
                // never grow when one is hidden.
                HardwareRingRowLayout(spacing: 6, referenceCount: HardwareRingSlot.allCases.count) {
                    ForEach(visibleSlots) { slot in
                        interactiveCard(slot)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(visibleSlots) { slot in
                        ringBase(slot, topAdjustment: 0)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .task(id: showsSSDCapacity) {
            // Only the visible SSD ring needs the one-shot volume lookup; a
            // CPU-only or GPU-only strip must not touch the filesystem.
            guard showsSSDCapacity else { return }
            if disk.freeBytes == nil { disk = DiskCapacitySample.current() }
            if externalVolumes.isEmpty { externalVolumes = DiskCapacityReader.externalVolumes() }
        }
    }

    private var showsSSDCapacity: Bool { visibleSlots.contains(.ssd) }

    /// Capacity of the external volumes the user ticked, summed. Empty selection
    /// gives a zero total, so the SSD card shows no external footer by default.
    private var selectedExternalTotals: (total: Int64, free: Int64) {
        externalVolumes
            .filter { ssdSelectedExternalPaths.contains($0.mountPath) }
            .reduce(into: (total: Int64(0), free: Int64(0))) { sum, volume in
                sum.total += Int64(volume.totalBytes)
                sum.free += Int64(volume.freeBytes)
            }
    }

    /// The ring scene for one slot, with the carded-mode top-text fix. `cardedSSD`
    /// turns the SSD card into the two-line footer layout (internal value above,
    /// selected external total below).
    private func ringBase(_ slot: HardwareRingSlot, topAdjustment: CGFloat, cardedSSD: Bool = false) -> some View {
        let spec = spec(for: slot, cardedSSD: cardedSSD)
        return AnimatedSceneIcon(
            label: slot.label,
            top: spec.top,
            center: spec.center,
            centerScale: spec.centerScale,
            color: spec.color,
            progress: spec.progress,
            topTextVerticalAdjustment: topAdjustment,
            animatesProgress: animatesProgress,
            splitGapProgress: splitGapProgress,
            footerPrimary: spec.footerPrimary,
            footerSecondary: spec.footerSecondary,
            footerNote: spec.footerNote
        )
        .animation(animatesProgress ? .easeOut(duration: 0.35) : nil, value: spec.progress)
    }

    /// One ring wrapped in its own card (status panel). Glass and material keep
    /// the shared silver surface; the opaque solid branch gets the neutral
    /// hardware surface with a palette-driven hover fill.
    private func ringCard(_ slot: HardwareRingSlot, hovered: Bool = false) -> some View {
        ringBase(slot, topAdjustment: Self.cardedTopTextAdjustment, cardedSSD: slot == .ssd)
            .padding(5)
            .hardwareMonitorCardSurface(.silver(.connected), cornerRadius: 13, hovered: hovered)
    }

    /// Carded ring plus pointer-enter glow and detail tap. Non-interactive when
    /// no callback is supplied (design preview).
    @ViewBuilder
    private func interactiveCard(_ slot: HardwareRingSlot) -> some View {
        if let onSelectSlot {
            Button { onSelectSlot(Self.detailKind(for: slot)) } label: {
                ringCard(slot, hovered: hoveredSlot == slot)
                    .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .overlay {
                if panelCardStyle != .solid {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(hoveredSlot == slot ? 0.06 : 0))
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if panelCardStyle != .solid {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(hoveredSlot == slot ? 0.22 : 0), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .onHover { inside in
                if inside { hoveredSlot = slot }
                else if hoveredSlot == slot { hoveredSlot = nil }
            }
            .accessibilityLabel(slot.label)
        } else {
            ringCard(slot)
        }
    }

    private static func detailKind(for slot: HardwareRingSlot) -> HardwareDetailKind {
        switch slot {
        case .cpu: return .cpu
        case .gpu: return .gpu
        case .ram: return .memory
        case .ssd: return .disk
        }
    }

    // MARK: - Slots

    private struct RingSlotSpec {
        var top: String
        var center: String
        var progress: Double
        var color: IconRGBA
        var centerScale: Double
        var footerPrimary: String?
        var footerSecondary: String?
        /// A small trailing note on the same line as the label, e.g. `+1500GB`
        /// for the external total. Keeps the label and the total on one compact
        /// baseline instead of stacking a second line.
        var footerNote: String? = nil
    }

    private func spec(for slot: HardwareRingSlot, cardedSSD: Bool = false) -> RingSlotSpec {
        switch slot {
        case .cpu:
            let useTemperature = temperatureMonitoringEnabled && cpuCenterContent == .temperature
            let center = useTemperature ? temperatureText(.cpuTemperature) : frequencyText()
            return RingSlotSpec(top: percentText(.cpuUsage), center: center, progress: percent(.cpuUsage),
                                color: color(.cpuUsage), centerScale: fittedCenterScale(center, base: 1.05),
                                footerPrimary: nil, footerSecondary: nil)
        case .gpu:
            let useTemperature = temperatureMonitoringEnabled && gpuCenterContent == .temperature
            let center = useTemperature ? temperatureText(.gpuTemperature) : "--"
            return RingSlotSpec(top: percentText(.gpuUsage), center: center, progress: percent(.gpuUsage),
                                color: color(.gpuUsage), centerScale: fittedCenterScale(center, base: 1.05),
                                footerPrimary: nil, footerSecondary: nil)
        case .ram:
            let value = HardwareRingValuePresentation.memory(
                usedPercent: sample(.memoryUsage)?.value,
                totalBytes: ProcessInfo.processInfo.physicalMemory,
                mode: memoryDisplayMode)
            return RingSlotSpec(top: value.topText, center: value.centerText, progress: value.progress,
                                color: color(.memoryUsage), centerScale: fittedCenterScale(value.centerText, base: 0.8),
                                footerPrimary: nil, footerSecondary: nil)
        case .ssd:
            let external = selectedExternalTotals
            let poolsExternals = ssdIncludeExternalInPercent && external.total > 0
            // The percentage (and arc) can pool the internal disk with the ticked
            // external volumes; the footer's first line still reports the
            // internal disk alone.
            let internalValue = HardwareRingValuePresentation.disk(
                usedFraction: disk.usedFraction, totalBytes: disk.totalBytes,
                freeBytes: disk.freeBytes, mode: ssdDisplayMode)
            var topText = internalValue.topText
            var progress = internalValue.progress
            if poolsExternals,
               let usedFraction = HardwareRingValuePresentation.combinedUsedFraction(
                   internalTotal: disk.totalBytes, internalFree: disk.freeBytes,
                   externalTotal: external.total, externalFree: external.free) {
                let combinedTotal = max(0, disk.totalBytes ?? 0) + max(0, external.total)
                let combinedFree = max(0, disk.freeBytes ?? 0) + max(0, external.free)
                let combined = HardwareRingValuePresentation.disk(
                    usedFraction: usedFraction, totalBytes: combinedTotal,
                    freeBytes: combinedFree, mode: ssdDisplayMode)
                topText = combined.topText
                progress = combined.progress
            }
            let externalNote: String? = (cardedSSD && external.total > 0)
                ? "+" + HardwareDetailFormat.compactDisk(Double(external.total)) : nil
            return RingSlotSpec(top: topText, center: internalValue.centerText, progress: progress,
                                color: diskColor, centerScale: fittedCenterScale(internalValue.centerText, base: 0.8),
                                footerPrimary: nil, footerSecondary: nil, footerNote: externalNote)
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

    /// Compact estimated CPU clock for the ring center, e.g. "3.2G".
    private func frequencyText() -> String {
        guard let frequency = hardware.snapshot.cpuFrequency else { return "--" }
        let value = frequency.performanceGHz ?? frequency.efficiencyGHz ?? frequency.superGHz
        guard let value, value.isFinite, value > 0 else { return "--" }
        return String(format: "%.1fG", value)
    }

}

/// Design preview: the shared four-ring strip under System Monitoring, wrapped
/// with the explanatory title and footnote.
struct MenuBarIconPreviewGrid: View {
    @ObservedObject var hardware: HardwareMonitorObservable
    let colors: [HardwareMonitorMetric: IconRGBA]
    var diskColor: IconRGBA = HardwareRingColorConfiguration.solidStateDriveColor

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

            HardwareRingStrip(hardware: hardware, colors: colors, diskColor: diskColor)

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

/// Builds the ring scene the panel and design-preview strip draw. Extracted from
/// `AnimatedRingLayer` so the split-gap option is unit-testable without a
/// SwiftUI host.
enum HardwareRingSceneBuilder {
    static func outerRing(progress: Double, color: IconRGBA, splitGapProgress: Bool) -> OuterRingState {
        OuterRingState(
            segments: [RingSegmentState(progress: progress, color: .custom(color))],
            gap: .value,
            layout: .standard,
            accessory: nil,
            strokeScale: 1.1,
            gapProgressMode: splitGapProgress ? .split : .absorbed
        )
    }
}

/// Renders only the app's real ring (no text) and lets the caller overlay static
/// text. Conforming to `Animatable` means only the ring's progress interpolates;
/// numeric/label text changes are siblings and update instantly.
private struct AnimatedRingLayer: View, Animatable {
    let color: IconRGBA
    var progress: Double
    var splitGapProgress: Bool = false

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
        let ring = HardwareRingSceneBuilder.outerRing(
            progress: progress,
            color: color,
            splitGapProgress: splitGapProgress
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
    /// Snap to new values instead of tweening when updated every second.
    var animatesProgress: Bool = true
    /// Draw the ring with progress split across the top gap (#375).
    var splitGapProgress: Bool = false
    /// When set, draws a two-line footer (primary above, optional secondary
    /// below) instead of the single bottom label. Used by the carded SSD ring to
    /// show the internal value over the selected external total.
    var footerPrimary: String? = nil
    var footerSecondary: String? = nil
    /// Small trailing note on the label line (e.g. `+1500GB` external total).
    var footerNote: String? = nil

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                AnimatedRingLayer(color: color, progress: progress, splitGapProgress: splitGapProgress)
                    .animation(animatesProgress ? .easeOut(duration: 0.35) : nil, value: progress)
                Text(top)
                    .font(.system(size: side * 0.166 * 1.1, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .offset(y: -side * 0.33 + topTextVerticalAdjustment)
                centerValueText(side: side)
                footerText(side: side)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func footerText(side: CGFloat) -> some View {
        if let footerPrimary {
            VStack(spacing: side * 0.012) {
                Text(footerPrimary)
                    .font(.system(size: side * 0.175, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let footerSecondary {
                    HStack(spacing: side * 0.025) {
                        Text("+")
                            .font(.system(size: side * 0.12, weight: .semibold, design: .rounded))
                        Text(footerSecondary)
                            .font(.system(size: side * 0.115, weight: .regular, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(width: side, alignment: .center)
            .multilineTextAlignment(.center)
        } else if let footerNote {
            Text(footerNote)
                .font(.system(size: side * 0.12, weight: .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .offset(y: side * 0.30)
        } else {
            Text(label)
                .font(.system(size: side * 0.14, weight: .regular))
                .foregroundStyle(.secondary)
                .offset(y: side * 0.30)
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
    let totalBytes: Int64?

    /// Placeholder used until the one-shot capacity read completes.
    static let empty = DiskCapacitySample(usedFraction: nil, freeBytes: nil, totalBytes: nil)

    static func current() -> DiskCapacitySample {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ])
        guard let total = values?.volumeTotalCapacity, total > 0 else {
            return .empty
        }
        let totalBytes = Int64(total)
        let free = values?.volumeAvailableCapacityForImportantUsage
        if let free {
            let used = max(0, min(1, 1 - Double(free) / Double(total)))
            return DiskCapacitySample(usedFraction: used, freeBytes: Int64(free), totalBytes: totalBytes)
        }
        return DiskCapacitySample(usedFraction: nil, freeBytes: nil, totalBytes: totalBytes)
    }
}
