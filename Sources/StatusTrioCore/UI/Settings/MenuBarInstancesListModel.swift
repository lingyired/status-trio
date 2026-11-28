import Foundation

enum MenuBarPreset: String, CaseIterable, Identifiable, Sendable {
    case network
    case cpuTemperature
    case gpuTemperature
    case memory
    case disk
    case power
    case fan
    case cpu
    case gpu

    var id: String { rawValue }

    var titleKey: LocalizationKey {
        switch self {
        case .network: return .menuBarPresetNetwork
        case .cpuTemperature: return .menuBarPresetCPUTemperature
        case .gpuTemperature: return .menuBarPresetGPUTemperature
        case .memory: return .menuBarPresetMemory
        case .disk: return .menuBarPresetDisk
        case .power: return .menuBarPresetPower
        case .fan: return .menuBarPresetFan
        case .cpu: return .menuBarPresetCPU
        case .gpu: return .menuBarPresetGPU
        }
    }

    func makeInstance() -> MenuBarInstance {
        let index = Self.allCases.firstIndex(of: self) ?? 0
        guard Self.templates.indices.contains(index) else {
            return MenuBarInstance(name: titleKey.rawValue, top: MenuBarLine())
        }
        var instance = Self.templates[index]
        instance.id = UUID()
        // The exported source accidentally routed both GPU presets to the CPU
        // detail page; the preset itself should always match its metric.
        if self == .gpuTemperature || self == .gpu {
            instance.clickAction = .panel("gpu")
        }
        return instance
    }

    /// Templates live in the bundled JSON so the presets stay editable as data
    /// rather than a large Swift literal. Instance names are replaced with the
    /// localized title when the editor inserts one.
    private static let templates: [MenuBarInstance] = {
        guard let url = Bundle.module.url(forResource: "MenuBarInstancePresets",
                                          withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? MenuBarInstanceTransfer.decodeAll(data)
        else { return [] }
        return document
    }()
}

/// Convenience layer over `SettingsStore` for the list screen. All mutations go
/// through the store so persistence and validation stay in one place.
@MainActor
struct MenuBarInstancesListModel {
    let store: SettingsStore
    static let limit = 20

    var instances: [MenuBarInstance] { store.menuBarInstances.instances }
    var canAdd: Bool { instances.count < Self.limit }

    /// Inserts a decoded/shared instance as a new item, assigning a fresh id so
    /// importing the same file twice cannot collide with the source instance.
    @discardableResult
    func importInstance(_ instance: MenuBarInstance) -> MenuBarInstance? {
        guard canAdd else { return nil }
        var imported = instance
        imported.id = UUID()
        store.updateMenuBarInstance(imported)
        return imported
    }

    func addPreset(_ preset: MenuBarPreset) {
        guard canAdd else { return }
        store.updateMenuBarInstance(preset.makeInstance())
    }

    func duplicate(id: UUID) {
        guard canAdd, let source = instances.first(where: { $0.id == id }) else { return }
        var copy = source
        copy.id = UUID()
        copy.name = source.name + " copy"
        store.updateMenuBarInstance(copy)
    }

    func delete(id: UUID) {
        store.deleteMenuBarInstance(id: id)
    }

    func move(from source: Int, to destination: Int) {
        store.moveMenuBarInstance(from: source, to: destination)
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard var instance = instances.first(where: { $0.id == id }) else { return }
        instance.isEnabled = enabled
        store.updateMenuBarInstance(instance)
    }
}
