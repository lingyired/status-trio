import Foundation

protocol TelemetrySending: Sendable {
    func sendIfNeeded(context: TelemetryContext) async
}

actor TelemetryClient: TelemetrySending {
    static let installationIDKey = "telemetry.installationId"
    static let lastAttemptAtKey = "telemetry.lastAttemptAt"
    static let lastSuccessfulAtKey = "telemetry.lastSuccessfulAt"

    private let transport: any TelemetryTransport
    private let configuration: TelemetryConfiguration
    private let now: @Sendable () -> Date
    private let defaults: UserDefaults
    private var isSending = false

    init(
        transport: any TelemetryTransport,
        configuration: TelemetryConfiguration,
        now: @escaping @Sendable () -> Date = { Date() },
        persistenceSuiteName: String? = nil
    ) {
        self.transport = transport
        self.configuration = configuration
        self.now = now
        if let persistenceSuiteName, let suiteDefaults = UserDefaults(suiteName: persistenceSuiteName) {
            defaults = suiteDefaults
        } else {
            defaults = .standard
        }
    }

    func sendIfNeeded(context: TelemetryContext) async {
        guard !Task.isCancelled, !isSending else { return }

        let attemptDate = now()
        if isWithinInterval(
            storedDate(forKey: Self.lastSuccessfulAtKey),
            interval: configuration.successMinimumInterval,
            at: attemptDate
        ) { return }
        if isWithinInterval(
            storedDate(forKey: Self.lastAttemptAtKey),
            interval: configuration.failureCooldown,
            at: attemptDate
        ) { return }
        guard !Task.isCancelled else { return }

        isSending = true
        defer { isSending = false }

        let installID: String
        if let storedID = defaults.string(forKey: Self.installationIDKey) {
            installID = storedID
        } else {
            guard !Task.isCancelled else { return }
            installID = UUID().uuidString
            defaults.set(installID, forKey: Self.installationIDKey)
        }

        defaults.set(attemptDate, forKey: Self.lastAttemptAtKey)
        let heartbeat = TelemetryHeartbeat(
            installID: installID,
            context: context,
            configuration: configuration
        )
        guard let body = try? JSONEncoder().encode(heartbeat), !Task.isCancelled else { return }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let response = try await transport.send(request: request)
            guard !Task.isCancelled, (200...299).contains(response.statusCode) else { return }
            defaults.set(now(), forKey: Self.lastSuccessfulAtKey)
        } catch {
            // Best effort by design. Do not log request identifiers or values.
        }
    }

    private func storedDate(forKey key: String) -> Date? {
        defaults.object(forKey: key) as? Date
    }

    private func isWithinInterval(_ storedDate: Date?, interval: TimeInterval, at now: Date) -> Bool {
        guard let storedDate else { return false }
        let elapsed = now.timeIntervalSince(storedDate)
        return elapsed < interval
    }
}
