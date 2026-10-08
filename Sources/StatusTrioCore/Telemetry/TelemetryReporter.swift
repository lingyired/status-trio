import AppKit
import Combine
import Foundation

@MainActor
final class TelemetryReporter {
    private let settings: SettingsStore
    private let localization: Localization
    private let client: any TelemetrySending
    private let isEligible: Bool
    private let configuration: TelemetryConfiguration
    private let wakeNotificationCenter: NotificationCenter
    private let sleep: @Sendable (Duration) async throws -> Void
    private let snapshotContext: @MainActor (AppLanguage, AppIconPlacement) -> TelemetryContext?

    private var consent: TelemetryConsent
    private var isStarted = false
    private var consentCancellable: AnyCancellable?
    private var wakeObserver: NSObjectProtocol?
    private var periodicTask: Task<Void, Never>?
    private var periodicTaskID: UUID?
    private var attemptTask: Task<Void, Never>?
    private var attemptTaskID: UUID?

    init(
        settings: SettingsStore,
        localization: Localization,
        client: any TelemetrySending,
        eligibilityContext: TelemetryEligibilityContext,
        configuration: TelemetryConfiguration,
        wakeNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
        snapshotContext: @escaping @MainActor (AppLanguage, AppIconPlacement) -> TelemetryContext?
    ) {
        self.settings = settings
        self.localization = localization
        self.client = client
        isEligible = TelemetryEligibility.isEligible(eligibilityContext)
        self.configuration = configuration
        self.wakeNotificationCenter = wakeNotificationCenter
        self.sleep = sleep
        self.snapshotContext = snapshotContext
        consent = settings.telemetryConsentSnapshot
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        guard isEligible else { return }

        consent = settings.telemetryConsentSnapshot
        consentCancellable = settings.telemetryConsentUpdates.sink { [weak self] updatedConsent in
            self?.receiveConsent(updatedConsent)
        }
        wakeObserver = wakeNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendIfNeeded()
            }
        }

        if consent.canShareAnonymousAnalytics {
            startPeriodicChecks()
            sendIfNeeded()
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        consentCancellable?.cancel()
        consentCancellable = nil
        if let wakeObserver {
            wakeNotificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        cancelAttempt()
        cancelPeriodicChecks()
    }

    /// Schedules a best-effort send while keeping the task owned by this reporter.
    func sendIfNeeded() {
        guard isStarted,
              isEligible,
              consent.canShareAnonymousAnalytics,
              attemptTask == nil else { return }

        let taskID = UUID()
        attemptTaskID = taskID
        attemptTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishAttempt(id: taskID) }
            guard self.isStarted,
                  self.isEligible,
                  self.consent.canShareAnonymousAnalytics,
                  !Task.isCancelled,
                  let context = self.snapshotContext(
                    self.localization.resolvedLanguage,
                    self.settings.appIconPlacement
                  ) else { return }
            await self.client.sendIfNeeded(context: context)
        }
    }

    private func receiveConsent(_ updatedConsent: TelemetryConsent) {
        let wasEnabled = consent.canShareAnonymousAnalytics
        consent = updatedConsent
        guard isStarted, isEligible else { return }
        if !consent.canShareAnonymousAnalytics {
            cancelAttempt()
            cancelPeriodicChecks()
            return
        }
        guard !wasEnabled else { return }
        startPeriodicChecks()
        sendIfNeeded()
    }

    private func startPeriodicChecks() {
        guard isStarted,
              isEligible,
              consent.canShareAnonymousAnalytics,
              periodicTask == nil else { return }

        let taskID = UUID()
        periodicTaskID = taskID
        let interval = Duration.milliseconds(
            Int(configuration.reporterCheckInterval * 1_000)
        )
        let sleepOperation = sleep
        periodicTask = Task { @MainActor [weak self, sleepOperation] in
            defer { self?.finishPeriodicChecks(id: taskID) }
            while !Task.isCancelled {
                do {
                    try await sleepOperation(interval)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                self.sendIfNeeded()
            }
        }
    }

    private func cancelAttempt() {
        attemptTask?.cancel()
        attemptTask = nil
        attemptTaskID = nil
    }

    private func cancelPeriodicChecks() {
        periodicTask?.cancel()
        periodicTask = nil
        periodicTaskID = nil
    }

    private func finishAttempt(id: UUID) {
        guard attemptTaskID == id else { return }
        attemptTask = nil
        attemptTaskID = nil
    }

    private func finishPeriodicChecks(id: UUID) {
        guard periodicTaskID == id else { return }
        periodicTask = nil
        periodicTaskID = nil
    }
}

@MainActor
protocol TelemetryReporting: AnyObject {
    func start()
    func stop()
}

extension TelemetryReporter: TelemetryReporting {}
