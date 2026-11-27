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
        // The instance list owns the visibility switch and writes straight to
        // the store. The editor edits its own copy, so adopt that field before
        // every write; otherwise renaming or adding an element would silently
        // turn a hidden instance back on.
        if let stored = store.menuBarInstances.instances.first(where: { $0.id == instance.id }) {
            instance.isEnabled = stored.isEnabled
        }
        store.updateMenuBarInstance(instance)
    }

    // MARK: - Layout

    func setLayoutMode(_ mode: MenuBarLayoutMode) {
        instance.layoutMode = mode
        persist()
    }

    // MARK: - Element editing

    @discardableResult
    func addTextElement(_ text: String = "Text", slot: MenuBarLineSlot) -> UUID? {
        append(MenuBarElement(content: .text(text)), slot: slot)
    }

    @discardableResult
    func addMetricElement(_ metric: MenuBarMetricID, slot: MenuBarLineSlot) -> UUID? {
        append(MenuBarElement(content: .metric(metric)), slot: slot)
    }

    @discardableResult
    func addIconElement(_ icon: MenuBarIconSpec, slot: MenuBarLineSlot) -> UUID? {
        append(MenuBarElement(content: .icon(icon)), slot: slot)
    }

    private func append(_ element: MenuBarElement, slot: MenuBarLineSlot) -> UUID? {
        guard elements(slot: slot).count < 32 else { return nil }
        mutateLine(slot) { $0.elements.append(element) }
        return element.id
    }

    func removeElement(id: UUID, slot: MenuBarLineSlot) {
        mutateLine(slot) { $0.elements.removeAll { $0.id == id } }
    }

    /// Inserts a new element from the library at a drop position.
    @discardableResult
    func insertElement(_ content: MenuBarElementContent, at index: Int, slot: MenuBarLineSlot) -> UUID? {
        guard elements(slot: slot).count < 32 else { return nil }
        let element = MenuBarElement(content: content)
        mutateLine(slot) { line in
            let target = min(max(0, index), line.elements.count)
            line.elements.insert(element, at: target)
        }
        return element.id
    }

    func moveElement(id: UUID, to destination: Int, slot: MenuBarLineSlot) {
        mutateLine(slot) { line in
            guard let current = line.elements.firstIndex(where: { $0.id == id }) else { return }
            let element = line.elements.remove(at: current)
            let target = min(max(0, destination), line.elements.count)
            line.elements.insert(element, at: target)
        }
    }

    func updateIcon(_ icon: MenuBarIconSpec, elementID: UUID, slot: MenuBarLineSlot) {
        mutateLine(slot) { line in
            guard let index = line.elements.firstIndex(where: { $0.id == elementID }) else { return }
            line.elements[index].content = .icon(icon)
        }
    }

    func updateText(_ text: String, elementID: UUID, slot: MenuBarLineSlot) {
        mutateLine(slot) { line in
            guard let index = line.elements.firstIndex(where: { $0.id == elementID }) else { return }
            line.elements[index].content = .text(text)
        }
    }

    /// Moves an element between lines (also used by cross-row drag/drop).
    func moveElement(id: UUID, from: MenuBarLineSlot, to: MenuBarLineSlot, index: Int = Int.max) {
        guard from != to else { return }
        var moved: MenuBarElement?
        mutateLine(from, persist: false) { line in
            guard let current = line.elements.firstIndex(where: { $0.id == id }) else { return }
            moved = line.elements.remove(at: current)
        }
        guard let element = moved else { persist(); return }
        mutateLine(to) { line in
            let target = min(max(0, index), line.elements.count)
            line.elements.insert(element, at: target)
        }
    }

    func elements(slot: MenuBarLineSlot) -> [MenuBarElement] {
        switch slot {
        case .top: return instance.top?.elements ?? []
        case .bottom: return instance.bottom?.elements ?? []
        }
    }

    // MARK: - Line / instance styling

    func setColor(_ color: LineColor, slot: MenuBarLineSlot) { mutateLine(slot) { $0.color = color } }
    func setAlignment(_ alignment: LineAlignment, slot: MenuBarLineSlot) { mutateLine(slot) { $0.alignment = alignment } }
    func setBold(_ bold: Bool, slot: MenuBarLineSlot) { mutateLine(slot) { $0.isBold = bold } }
    func setMonospacedDigits(_ on: Bool, slot: MenuBarLineSlot) { mutateLine(slot) { $0.usesMonospacedDigits = on } }
    func setFontSize(_ size: Double?, slot: MenuBarLineSlot) {
        mutateLine(slot) { line in
            line.fontSize = size.map { min(18, max(8, $0)) }
        }
    }


    func setLeadingIcon(_ icon: MenuBarIconSpec?) {
        instance.leadingIcon = icon
        persist()
    }

    func setLeadingIcon(_ icon: MenuBarIconSpec?, slot: MenuBarLineSlot) {
        mutateLine(slot) { $0.leadingIcon = icon }
    }

    func setLeadingIconSize(_ size: Double, slot: MenuBarLineSlot) {
        mutateLine(slot) { $0.leadingIconSize = min(16, max(10, size)) }
    }

    func setLeadingIconColor(_ color: ColorValue?, slot: MenuBarLineSlot) {
        mutateLine(slot) { $0.leadingIconColor = color }
    }

    func setMinimumWidth(_ width: Double) {
        instance.minimumWidth = width <= 0 ? nil : min(400, max(20, width))
        persist()
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

    func previewImage(dark: Bool = true) -> NSImage? {
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
        let input = MenuBarRenderInput(
            instance: instance,
            readings: readings,
            colorOverrides: store.hardwareMonitorMetricColors
        )
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance(named: .aqua)!
        return MenuBarInstanceRenderer.render(input, appearance: appearance, scale: 2)
    }

    // MARK: - Helpers

    private func mutateLine(_ slot: MenuBarLineSlot, persist shouldPersist: Bool = true, _ body: (inout MenuBarLine) -> Void) {
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
        if shouldPersist { persist() }
    }
}
