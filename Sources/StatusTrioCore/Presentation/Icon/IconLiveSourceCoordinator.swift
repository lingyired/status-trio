import Foundation

/// Host-owned subscription coordinator for live icon sources.
///
/// Consumers are slots on a surface (`menuBar.outerRing`, `dock.center`, …).
/// The same binding used by several consumers starts at most once, and stops
/// only when the last consumer lets go. Every activation receives a generation
/// token so a late callback from a previous subscription can be dropped before
/// it overwrites the value of a newer source.
@MainActor
final class IconLiveSourceCoordinator {
    struct Consumer: Hashable, Sendable {
        let surface: String
        let slot: IconSlot

        init(surface: String, slot: IconSlot) {
            self.surface = surface
            self.slot = slot
        }
    }

    struct SubscriptionToken: Hashable, Sendable {
        let binding: IconContentBinding
        let generation: Int
    }

    private var owners: [Consumer: Set<IconContentBinding>] = [:]
    private var generations: [IconContentBinding: Int] = [:]
    private var active: Set<IconContentBinding> = []
    private let start: (SubscriptionToken) -> Void
    private let stop: (IconContentBinding) -> Void
    private let onChange: (Set<IconContentBinding>) -> Void

    init(
        start: @escaping (SubscriptionToken) -> Void,
        stop: @escaping (IconContentBinding) -> Void,
        onChange: @escaping (Set<IconContentBinding>) -> Void = { _ in }
    ) {
        self.start = start
        self.stop = stop
        self.onChange = onChange
    }

    var activeBindings: Set<IconContentBinding> { active }

    func setBindings(_ bindings: Set<IconContentBinding>, for consumer: Consumer) {
        owners[consumer] = bindings
        rebuild()
    }

    func removeConsumer(_ consumer: Consumer) {
        guard owners.removeValue(forKey: consumer) != nil else { return }
        rebuild()
    }

    func removeAll() {
        owners.removeAll()
        rebuild()
    }

    /// True while `token` is the current activation for its binding.
    func accepts(_ token: SubscriptionToken) -> Bool {
        active.contains(token.binding) && generations[token.binding] == token.generation
    }

    func token(for binding: IconContentBinding) -> SubscriptionToken? {
        guard active.contains(binding), let generation = generations[binding] else { return nil }
        return SubscriptionToken(binding: binding, generation: generation)
    }

    private func rebuild() {
        var counts: [IconContentBinding: Int] = [:]
        for bindings in owners.values {
            for binding in bindings { counts[binding, default: 0] += 1 }
        }
        let next = Set(counts.keys)

        for binding in active.subtracting(next).sorted(by: Self.isOrderedBefore) {
            active.remove(binding)
            stop(binding)
        }
        for binding in next.subtracting(active).sorted(by: Self.isOrderedBefore) {
            let generation = (generations[binding] ?? 0) + 1
            generations[binding] = generation
            active.insert(binding)
            start(SubscriptionToken(binding: binding, generation: generation))
        }
        onChange(active)
    }

    private static func isOrderedBefore(_ lhs: IconContentBinding, _ rhs: IconContentBinding) -> Bool {
        (lhs.pluginID, lhs.presentationID) < (rhs.pluginID, rhs.presentationID)
    }
}

/// Coalesces externally-triggered icon resolutions.
///
/// The first request runs immediately, later requests inside the minimum
/// interval collapse into one trailing run, and the clock is injectable so the
/// rate limit is testable without sleeping. The trailing action is always kept,
/// so a continuous stream cannot starve the last value.
@MainActor
final class IconLiveResolutionCoalescer {
    struct Timing {
        let now: () -> Date
        let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void

        static func live() -> Self {
            Self(
                now: { Date() },
                schedule: { delay, action in
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        Task { @MainActor in action() }
                    }
                }
            )
        }
    }

    let minimumInterval: TimeInterval
    private let timing: Timing
    private var lastRun: Date?
    private var pending: (@MainActor () -> Void)?
    private var scheduled = false
    private var generation = 0

    init(minimumInterval: TimeInterval = 0.25, timing: Timing) {
        self.minimumInterval = minimumInterval
        self.timing = timing
    }

    func request(_ action: @escaping @MainActor () -> Void) {
        pending = action
        let elapsed = timing.now().timeIntervalSince(lastRun ?? .distantPast)
        if elapsed >= minimumInterval {
            runPending()
        } else if !scheduled {
            scheduled = true
            generation += 1
            let expected = generation
            timing.schedule(max(0, minimumInterval - elapsed)) { [weak self] in
                guard let self, self.generation == expected else { return }
                self.scheduled = false
                self.runPending()
            }
        }
    }

    func cancel() {
        generation += 1
        scheduled = false
        pending = nil
    }

    private func runPending() {
        guard let action = pending else { return }
        pending = nil
        lastRun = timing.now()
        action()
    }
}
