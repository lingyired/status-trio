import Foundation

enum MenuBarPreset: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case temperature
    case memory
    case network
    case battery

    var id: String { rawValue }

    var titleKey: LocalizationKey {
        switch self {
        case .cpu: return .hardwareMonitorCPU
        case .temperature: return .hardwareMonitorTemperature
        case .memory: return .hardwareMonitorMemory
        case .network: return .hardwareMonitorDownload
        case .battery: return .hardwareMonitorBattery
        }
    }

    func makeInstance() -> MenuBarInstance {
        switch self {
        case .cpu:
            return MenuBarInstance(name: "CPU", top: MenuBarLine(elements: [MenuBarElement(content: .text("CPU ")), MenuBarElement(content: .metric(.cpuUsage))]))
        case .temperature:
            return MenuBarInstance(name: "CPU Temp", top: MenuBarLine(elements: [MenuBarElement(content: .metric(.cpuTemperature))]))
        case .memory:
            return MenuBarInstance(name: "Memory", top: MenuBarLine(elements: [MenuBarElement(content: .metric(.memoryUsage))]))
        case .network:
            return MenuBarInstance(name: "Network", top: MenuBarLine(elements: [MenuBarElement(content: .metric(.networkDownload))]))
        case .battery:
            return MenuBarInstance(name: "Battery", top: MenuBarLine(elements: [MenuBarElement(content: .metric(.batteryLevel))]))
        }
    }
}

/// Convenience layer over `SettingsStore` for the list screen. All mutations go
/// through the store so persistence and validation stay in one place.
@MainActor
struct MenuBarInstancesListModel {
    let store: SettingsStore
    static let limit = 20

    var instances: [MenuBarInstance] { store.menuBarInstances.instances }
    var canAdd: Bool { instances.count < Self.limit }

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
