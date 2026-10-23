import Combine
import Foundation

enum GlobalShortcutRegistrationFailure: Error, Equatable, Sendable {
    case conflict
    case other
}

enum GlobalShortcutFeedback: Equatable, Sendable {
    case invalidCombination
    case inputMethodConflict
    case conflict
    case registrationFailed
    case restorationFailed

    var localizationKey: LocalizationKey {
        switch self {
        case .invalidCombination:
            return .settingsShortcutInvalid
        case .inputMethodConflict:
            return .settingsShortcutInputMethodConflict
        case .conflict:
            return .settingsShortcutUnavailable
        case .registrationFailed:
            return .settingsShortcutRegistrationFailed
        case .restorationFailed:
            return .settingsShortcutRestorationFailed
        }
    }
}

@MainActor
protocol GlobalShortcutRegistering: AnyObject {
    func register(
        _ shortcut: StatusPanelShortcut,
        action: @escaping @MainActor () -> Void
    ) throws -> UUID
    func unregister(_ token: UUID)
    func stop()
}

@MainActor
final class GlobalShortcutController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var feedback: GlobalShortcutFeedback?

    private let settings: SettingsStore
    private let backend: any GlobalShortcutRegistering
    private let action: @MainActor () -> Void
    private var activeToken: UUID?
    private var activationGeneration: UInt64 = 0
    private var isStarted = false

    init(
        settings: SettingsStore,
        backend: any GlobalShortcutRegistering,
        action: @escaping @MainActor () -> Void
    ) {
        self.settings = settings
        self.backend = backend
        self.action = action
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        feedback = nil
        registerStoredShortcutIfNeeded()
    }

    func stop() {
        isStarted = false
        isRecording = false
        activeToken = nil
        activationGeneration &+= 1
        feedback = nil
        backend.stop()
    }

    func setShortcut(_ shortcut: StatusPanelShortcut) -> Bool {
        guard isStarted else {
            feedback = .registrationFailed
            return false
        }
        guard !shortcut.isKnownInputMethodConflict else {
            feedback = .inputMethodConflict
            return false
        }

        if settings.statusPanelShortcut == shortcut {
            isRecording = false
            feedback = nil
            registerStoredShortcutIfNeeded()
            return activeToken != nil || settings.statusPanelShortcut == nil
        }

        let previousToken = activeToken
        let candidateGeneration = activationGeneration &+ 1
        do {
            let candidateToken = try register(
                shortcut,
                generation: candidateGeneration
            )
            activationGeneration = candidateGeneration
            if let previousToken {
                backend.unregister(previousToken)
            }
            activeToken = candidateToken
            settings.statusPanelShortcut = shortcut
            isRecording = false
            feedback = nil
            return true
        } catch {
            feedback = Self.feedback(for: error)
            // During recording the old registration stays suspended. Restoring
            // it here would let Carbon consume the very combination the native
            // recorder is trying to capture.
            activeToken = previousToken
            return false
        }
    }

    func beginRecording() {
        guard isStarted, !isRecording else { return }
        isRecording = true
        feedback = nil
        activationGeneration &+= 1
        if let activeToken {
            backend.unregister(activeToken)
            self.activeToken = nil
        }
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        if feedback == .invalidCombination || feedback == .inputMethodConflict {
            feedback = nil
        }
        registerStoredShortcutIfNeeded(reportRestorationFailure: true)
    }

    func cancelRecording() {
        feedback = nil
        endRecording()
    }

    func reportInvalidShortcut() {
        guard isRecording else { return }
        feedback = .invalidCombination
    }

    func clearShortcut() {
        activationGeneration &+= 1
        if let activeToken {
            backend.unregister(activeToken)
            self.activeToken = nil
        }
        settings.statusPanelShortcut = nil
        isRecording = false
        feedback = nil
    }

    private func registerStoredShortcutIfNeeded(
        reportRestorationFailure: Bool = false
    ) {
        guard isStarted,
              !isRecording,
              activeToken == nil,
              let shortcut = settings.statusPanelShortcut else {
            return
        }
        guard !shortcut.isKnownInputMethodConflict else {
            activeToken = nil
            feedback = .inputMethodConflict
            return
        }
        do {
            activeToken = try makeRegistration(for: shortcut)
        } catch {
            activeToken = nil
            feedback = reportRestorationFailure
                ? .restorationFailed
                : Self.feedback(for: error)
        }
    }

    private func makeRegistration(for shortcut: StatusPanelShortcut) throws -> UUID {
        let generation = activationGeneration &+ 1
        let token = try register(shortcut, generation: generation)
        activationGeneration = generation
        return token
    }

    private func register(
        _ shortcut: StatusPanelShortcut,
        generation: UInt64
    ) throws -> UUID {
        try backend.register(shortcut) { [weak self] in
            self?.handleActivation(generation: generation)
        }
    }

    private func handleActivation(generation: UInt64) {
        guard isStarted,
              !isRecording,
              activeToken != nil,
              generation == activationGeneration else {
            return
        }
        action()
    }

    private static func feedback(for error: Error) -> GlobalShortcutFeedback {
        if error as? GlobalShortcutRegistrationFailure == .conflict {
            return .conflict
        }
        return .registrationFailed
    }
}
