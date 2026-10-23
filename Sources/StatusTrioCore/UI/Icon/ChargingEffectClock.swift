import Combine
import Foundation

@MainActor
final class ChargingEffectClock: ObservableObject {
    static let tickInterval = Duration.milliseconds(50)
    // Subtracting two Date values can compound their ~120-ns absolute precision
    // near the present epoch; allow a 500-ns clock-edge snap (1e-5 of a frame).
    private static let frameBoundaryTolerance = 1e-5 / Double(ChargingEffectTimeline.framesPerSecond)
    private static let frameBoundaryToleranceInFrames = 1e-5
    private static let heartbeatDuration: TimeInterval = 0.25

    @Published private(set) var phase: ChargingEffectPhase?
    @Published private(set) var isRunning = false

    private let now: () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private var task: Task<Void, Never>?
    private var battery: BatteryStatus = .placeholder
    private var previousBattery: BatteryStatus? = .placeholder
    private var enabled = false
    private var reduceMotion = false
    private var displayAsleep = false
    /// The menu bar is the animation's own surface; the settings preview can keep
    /// the clock alive while the item is hidden (Dock-only placement).
    private var menuBarVisible = true
    private var previewConsumers: Set<AnyHashable> = []
    /// The Dock tile is a second surface. It is claimed only while the user's
    /// own placement really has a Dock tile on screen, so a window that makes
    /// the app regular for a moment never starts the animation.
    private var dockAnimationActive = false
    private var menuPlugInBurstStartedAt: Date?
    private var steadyStartedAt: Date?
    private var boostedHeartbeatCycle: Int?

    init(
        now: @escaping () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.now = now
        self.sleep = sleep
    }

    /// `true` while something on screen draws the live phase. Without a surface
    /// the 20-Hz tick is pure work: nothing would render it.
    var hasAnimationSurface: Bool {
        menuBarVisible || !previewConsumers.isEmpty || dockAnimationActive
    }

    /// Whether the Dock tile is currently a surface for the live phase.
    var isDockAnimationActive: Bool { dockAnimationActive }

    /// Claims or releases the Dock tile. Idempotent, so a repeated eligibility
    /// update cannot leave a second tick loop behind, and the battery state is
    /// untouched: resuming never replays the plug-in burst for a charge that is
    /// already in progress.
    func setDockAnimationActive(_ isActive: Bool) {
        guard dockAnimationActive != isActive else { return }
        dockAnimationActive = isActive
        reevaluate()
    }

    /// A view that draws the live phase claims the clock while it is on screen.
    /// Claims are token-based so a repeated appear/disappear cannot leak one.
    func beginAnimationPreview(_ token: AnyHashable) {
        guard previewConsumers.insert(token).inserted else { return }
        reevaluate()
    }

    func endAnimationPreview(_ token: AnyHashable) {
        guard previewConsumers.remove(token) != nil else { return }
        reevaluate()
    }

    func update(
        battery: BatteryStatus,
        enabled: Bool,
        reduceMotion: Bool,
        displayAsleep: Bool,
        menuBarVisible: Bool = true
    ) {
        let priorBattery = previousBattery
        previousBattery = battery
        self.battery = battery
        self.enabled = enabled
        self.reduceMotion = reduceMotion
        self.displayAsleep = displayAsleep
        self.menuBarVisible = menuBarVisible

        guard shouldAnimate else {
            stop()
            return
        }

        let event = priorBattery.map {
            ChargingEffectEvent.between(previous: $0, current: battery)
        } ?? nil

        if task == nil {
            let eventDate = now()
            beginTimeline(for: event, at: eventDate)
            if event == .levelAdvanced {
                scheduleHeartbeatBoost(at: eventDate)
            }
            start()
            return
        }

        let eventDate = now()
        switch event {
        case .pluggedIn:
            beginTimeline(for: .pluggedIn, at: eventDate)
        case .levelAdvanced:
            scheduleHeartbeatBoost(at: eventDate)
        case nil:
            break
        }
        let phaseDate = now()
        phase = phase(at: phaseDate)
    }

    func start() {
        guard task == nil, shouldAnimate else { return }

        if steadyStartedAt == nil {
            beginTimeline(for: nil, at: now())
        }
        isRunning = true
        let phaseDate = now()
        phase = phase(at: phaseDate)

        let sleep = self.sleep
        let tickInterval = Self.tickInterval
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleep(tickInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                let phaseDate = self.now()
                self.phase = self.phase(at: phaseDate)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        phase = nil
        menuPlugInBurstStartedAt = nil
        steadyStartedAt = nil
        boostedHeartbeatCycle = nil
    }

    private func beginTimeline(for event: ChargingEffectEvent?, at date: Date) {
        boostedHeartbeatCycle = nil
        switch event {
        case .pluggedIn:
            menuPlugInBurstStartedAt = date
            steadyStartedAt = date.addingTimeInterval(ChargingEffectTimeline.burstDuration)
        case .levelAdvanced:
            menuPlugInBurstStartedAt = nil
            steadyStartedAt = date
        case nil:
            menuPlugInBurstStartedAt = nil
            steadyStartedAt = date
        }
    }

    private var shouldAnimate: Bool {
        ChargingEffectPolicy.shouldAnimate(
            battery: battery,
            enabled: enabled,
            reduceMotion: reduceMotion,
            displayAsleep: displayAsleep
        ) && hasAnimationSurface
    }

    /// Re-evaluates the tick loop after a claim or the menu bar's visibility
    /// changed. The battery state is untouched, so resuming never invents a
    /// plug-in burst: `update` is what decides that, and it compares batteries.
    private func reevaluate() {
        if shouldAnimate {
            start()
        } else {
            stop()
        }
    }

    private func scheduleHeartbeatBoost(at date: Date) {
        guard let steadyStartedAt else { return }
        let elapsed = max(0, date.timeIntervalSince(steadyStartedAt))
        let adjustedElapsed = elapsed + Self.frameBoundaryTolerance
        let cycleDuration = ChargingEffectTimeline.steadyCycleDuration
        let cycleIndex = Int((adjustedElapsed / cycleDuration).rounded(.down))
        let cycleElapsed = adjustedElapsed.truncatingRemainder(dividingBy: cycleDuration)
        let heartbeatStartsAt = cycleDuration - Self.heartbeatDuration
        boostedHeartbeatCycle = cycleIndex + (cycleElapsed >= heartbeatStartsAt ? 1 : 0)
    }

    private func phase(at date: Date) -> ChargingEffectPhase? {
        guard let steadyStartedAt else { return nil }

        if let menuPlugInBurstStartedAt {
            if let burstPhase = burstPhase(
                event: .pluggedIn,
                startedAt: menuPlugInBurstStartedAt,
                at: date
            ) {
                return burstPhase
            }
            self.menuPlugInBurstStartedAt = nil
        }

        let steadyElapsed = max(0, date.timeIntervalSince(steadyStartedAt))
        let adjustedElapsed = steadyElapsed + Self.frameBoundaryTolerance
        let cycleDuration = ChargingEffectTimeline.steadyCycleDuration
        let cycleIndex = Int((adjustedElapsed / cycleDuration).rounded(.down))
        let multiplier = cycleIndex == boostedHeartbeatCycle ? 1.35 : 1
        return ChargingEffectTimeline.phase(
            elapsed: adjustedElapsed,
            kind: .steady,
            heartbeatMultiplier: multiplier
        )
    }

    private func burstPhase(
        event: ChargingEffectEvent,
        startedAt: Date,
        at date: Date
    ) -> ChargingEffectPhase? {
        let burstElapsed = max(0, date.timeIntervalSince(startedAt))
        let adjustedElapsed = burstElapsed + Self.frameBoundaryTolerance
        let burstFramePosition = adjustedElapsed * Double(ChargingEffectTimeline.framesPerSecond)
        let burstDuration = ChargingEffectTimeline.cycleDuration(for: .burst, event: event)
        let burstFrameCount = Double(
            (burstDuration * Double(ChargingEffectTimeline.framesPerSecond)).rounded()
        )
        guard burstFramePosition + Self.frameBoundaryToleranceInFrames < burstFrameCount else {
            return nil
        }
        return ChargingEffectTimeline.phase(
            elapsed: adjustedElapsed,
            kind: .burst,
            event: event
        )
    }
}
