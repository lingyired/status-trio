import Foundation

/// Pure, testable owner of one Sparkle update cycle's source context.
struct UpdateCycleState {
    enum Phase: Equatable, Sendable {
        case idle
        case checking
        case downloading
        case installing
    }

    private(set) var phase: Phase = .idle
    private(set) var preference: UpdatePreference = .githubFirst
    private(set) var fallback = UpdateSourceFallback()

    var isActive: Bool { phase != .idle }

    private(set) var isManual = false

    var isGiteeFirstCycle: Bool { isActive && preference == .giteeFirst }

    mutating func advanceForTest(_ error: Error?) -> Bool {
        fallback.advanceAfterError(error)
    }

    mutating func resetForTest() {
        fallback = UpdateSourceFallback()
    }

    mutating func beginManual(preference: UpdatePreference) -> Bool {
        // A feedURL lookup at Sparkle startup can create an idle automatic
        // context. Manual checks are allowed to replace that context; a real
        // manual cycle is still protected by canCheckForUpdates.
        guard !isActive || !isManual else { return false }
        self.preference = preference
        self.fallback = UpdateSourceFallback(preference: preference)
        isManual = true
        phase = .checking
        return true
    }

    mutating func beginAutomaticIfIdle() -> Bool {
        guard !isActive else { return false }
        preference = .githubFirst
        fallback = UpdateSourceFallback(preference: .githubFirst)
        isManual = false
        phase = .checking
        return true
    }

    mutating func markDownloading() {
        guard phase == .checking else { return }
        phase = .downloading
    }

    mutating func markInstalling() {
        guard phase == .checking || phase == .downloading else { return }
        phase = .installing
    }

    func appcastURLString(from directURLString: String) -> String? {
        fallback.appcastURLString(from: directURLString)
    }

    func downloadURL(for appcastURL: URL) -> URL {
        fallback.downloadURL(for: appcastURL)
    }

    /// Called only when Sparkle reports the cycle finished; an in-flight
    /// download never reaches this point, so the source cannot change mid-download.
    mutating func prepareForRetryAfterFinishedCycle() {
        if phase == .downloading { phase = .checking }
    }

    func canAdvanceAfterError(_ error: Error?) -> Bool {
        guard phase == .checking else { return false }
        return fallback.canAdvanceAfterError(error)
    }

    /// Suppression is a UI decision before Sparkle finishes the cycle; it may
    /// include a download failure that is retried after the cycle ends.
    func canSuppressErrorForRetry(_ error: Error?) -> Bool {
        guard phase == .checking || phase == .downloading else { return false }
        return fallback.canAdvanceAfterError(error)
    }

    mutating func advanceAfterError(_ error: Error?) -> Bool {
        guard phase == .checking else { return false }
        return fallback.advanceAfterError(error)
    }

    /// Ends the cycle and makes the next background check GitHub-first again.
    mutating func finish() {
        phase = .idle
        isManual = false
        preference = .githubFirst
        fallback = UpdateSourceFallback()
    }
}
