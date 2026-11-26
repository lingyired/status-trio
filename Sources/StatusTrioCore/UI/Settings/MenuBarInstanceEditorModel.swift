import AppKit
import Foundation

/// Edits one instance. Every mutation writes back through `SettingsStore` so the
/// live status item updates through the same subscription path the app uses.
@MainActor
final class MenuBarInstanceEditorModel: ObservableObject {
    @Published var instance: MenuBarInstance
    private let store: SettingsStore

    init(instance: MenuBarInstance, store: SettingsStore) {
        self.instance = instance
        self.store = store
    }

    func persist() {
        store.updateMenuBarInstance(instance)
    }

    // MARK: - Segment editing

    func addTextSegment(_ text: String = "Text", slot: MenuBarLineSlot) {
        mutateLine(slot) { $0.segments.append(.text(text)) }
    }

    func addMetricSegment(_ metric: MenuBarMetricID, slot: MenuBarLineSlot) {
        mutateLine(slot) { $0.segments.append(.metric(metric)) }
    }

    func removeSegment(at index: Int, slot: MenuBarLineSlot) {
        mutateLine(slot) { line in
            guard line.segments.indices.contains(index) else { return }
            line.segments.remove(at: index)
        }
    }

    func moveSegment(from source: Int, to destination: Int, slot: MenuBarLineSlot) {
        mutateLine(slot) { line in
            guard line.segments.indices.contains(source) else { return }
            let item = line.segments.remove(at: source)
            let target = min(max(0, destination), line.segments.count)
            line.segments.insert(item, at: target)
        }
    }

    func updateText(_ text: String, at index: Int, slot: MenuBarLineSlot) {
        mutateLine(slot) { line in
            guard line.segments.indices.contains(index) else { return }
            line.segments[index] = .text(text)
        }
    }

    // MARK: - Line / instance styling

    func setColor(_ color: LineColor, slot: MenuBarLineSlot) {
        mutateLine(slot) { $0.color = color }
    }

    func setAlignment(_ alignment: LineAlignment, slot: MenuBarLineSlot) {
        mutateLine(slot) { $0.alignment = alignment }
    }

    func setBold(_ bold: Bool, slot: MenuBarLineSlot) {
        mutateLine(slot) { $0.isBold = bold }
    }

    func setIcon(_ icon: MenuBarIconSpec?, slot: MenuBarLineSlot) {
        mutateLine(slot) { $0.icon = icon }
    }

    func setPadding(inner: Double, outer: Double) {
        instance.innerPadding = min(24, max(0, inner))
        instance.outerMargin = min(24, max(0, outer))
        persist()
    }

    func setActivation(click: InstanceActivation, hover: InstanceActivation, rightClick: InstanceRightClick) {
        instance.clickAction = click
        instance.hoverAction = hover
        instance.rightClick = rightClick
        persist()
    }

    func setName(_ name: String) {
        instance.name = name
        persist()
    }

    // MARK: - Preview

    /// Renders a preview with a mock snapshot. Never creates a status item and
    /// never registers sampling demand.
    func previewImage() -> NSImage? {
        var readings: [MenuBarMetricID: MenuBarMetricReading] = [:]
        for metric in instance.allMetrics {
            if metric == .wifiConnectionStatus {
                readings[metric] = MenuBarMetricReading(text: "Connected", value: nil, availability: .measured)
            } else {
                readings[metric] = MenuBarMetricReading(
                    text: MenuBarMetricRegistry.format(42, for: metric),
                    value: 42,
                    availability: .measured
                )
            }
        }
        let input = MenuBarRenderInput(instance: instance, readings: readings)
        let appearance = NSAppearance(named: .darkAqua) ?? NSAppearance(named: .aqua)!
        return MenuBarInstanceRenderer.render(input, appearance: appearance, scale: 2)
    }

    // MARK: - Helpers

    private func mutateLine(_ slot: MenuBarLineSlot, _ body: (inout MenuBarLine) -> Void) {
        switch slot {
        case .top:
            var line = instance.top ?? MenuBarLine()
            body(&line)
            instance.top = line
        case .bottom:
            var line = instance.bottom ?? MenuBarLine()
            body(&line)
            instance.bottom = line
        }
        persist()
    }
}
