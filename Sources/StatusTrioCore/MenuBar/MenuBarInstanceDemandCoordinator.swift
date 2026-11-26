import Foundation

/// Registers one demand owner per enabled instance. Two instances that show the
/// same metric share a single underlying sample; disabling or removing an
/// instance releases only its own owner, never another's.
@MainActor
final class MenuBarInstanceDemandCoordinator {
    private let register: (String, Set<HardwareMetricID>) -> Void
    private let unregister: (String) -> Void
    private(set) var registeredOwners: [String: Set<HardwareMetricID>] = [:]

    init(
        register: @escaping (String, Set<HardwareMetricID>) -> Void,
        unregister: @escaping (String) -> Void
    ) {
        self.register = register
        self.unregister = unregister
    }

    static func ownerID(for id: UUID) -> String {
        "menuBarInstance:\(id.uuidString)"
    }

    func metricSet(for instance: MenuBarInstance) -> Set<HardwareMetricID> {
        Set(instance.demandedMetrics.compactMap { MenuBarMetricRegistry.hardwareMetricID(for: $0) })
    }

    func setInstances(_ instances: [MenuBarInstance]) {
        var next: [String: Set<HardwareMetricID>] = [:]
        for instance in instances where instance.isEnabled && instance.hasVisibleContent {
            next[Self.ownerID(for: instance.id)] = metricSet(for: instance)
        }
        for key in registeredOwners.keys where next[key] == nil {
            unregister(key)
        }
        for (key, metrics) in next where registeredOwners[key] != metrics {
            register(key, metrics)
        }
        registeredOwners = next
    }

    var mergedMetrics: Set<HardwareMetricID> {
        registeredOwners.values.reduce(into: Set<HardwareMetricID>()) { $0.formUnion($1) }
    }
}
