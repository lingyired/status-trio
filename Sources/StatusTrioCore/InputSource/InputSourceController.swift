import Combine
import Foundation

/// Wraps the distributed notification centre so tests can drive the two TIS
/// change signals without a real system event.
@MainActor
protocol InputSourceNotificationObserving: AnyObject {
    func observe(
        _ name: Notification.Name,
        handler: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol
    func remove(_ token: NSObjectProtocol)
}

@MainActor
final class SystemInputSourceNotificationObserver: InputSourceNotificationObserving {
    private let center: DistributedNotificationCenter

    init(center: DistributedNotificationCenter = .default()) {
        self.center = center
    }

    func observe(
        _ name: Notification.Name,
        handler: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        center.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in
                handler()
            }
        }
    }

    func remove(_ token: NSObjectProtocol) {
        center.removeObserver(token)
    }
}

@MainActor
protocol InputSourceConfirmationScheduling: AnyObject {
    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
final class TaskInputSourceConfirmationScheduler: InputSourceConfirmationScheduling {
    private var task: Task<Void, Never>?

    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.task = nil
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// The single source of truth for input-source state, shared by the centre
/// icon and the status panel.
///
/// Reads once at `start()` and then follows the two TIS change notifications;
/// there is no polling. The menu bar / Dock lifecycle calls `start()` only
/// while a feature that needs it is enabled, so a user who never turns the
/// feature on never pays for an observer.
@MainActor
final class InputSourceController: ObservableObject {
    /// Why a click on a source row did not end in the source being selected.
    /// Kept next to, but separate from, the state the icon draws: a transient
    /// failure must never change the icon's truth.
    struct SelectionFailure: Equatable, Sendable {
        enum Reason: Equatable, Sendable {
            /// The ID is not one of the enabled, select-capable sources.
            case unknownSource
            /// `TISSelectInputSource` returned a non-zero status.
            case systemRefused(osStatus: Int32)
            /// The call returned `noErr` but the system still reports another
            /// source as current after the confirmation window.
            case notConfirmed
        }

        let sourceID: String
        let reason: Reason
    }

    /// How many times a `noErr` selection is re-checked, 80 ms apart. Bounded:
    /// the check only decides which feedback text to show, it never flips what
    /// the icon considers true.
    static let confirmationAttempts = 4
    static let confirmationInterval: Duration = .milliseconds(80)

    @Published private(set) var state: InputSourceState = .empty
    @Published private(set) var selectionFailure: SelectionFailure?

    var selectedDescriptor: InputSourceDescriptor? {
        state.selectedDescriptor
    }

    private let reader: any InputSourceReading
    private let switcher: any InputSourceSwitching
    private let notifications: any InputSourceNotificationObserving
    private let confirmationScheduler: any InputSourceConfirmationScheduling
    private var observationTokens: [NSObjectProtocol] = []
    private var confirmationGeneration = 0
    private var isStarted = false

    init(
        reader: any InputSourceReading = SystemInputSourceReader(),
        switcher: any InputSourceSwitching = SystemInputSourceSwitcher(),
        notifications: (any InputSourceNotificationObserving)? = nil,
        confirmationScheduler: any InputSourceConfirmationScheduling = TaskInputSourceConfirmationScheduler()
    ) {
        self.reader = reader
        self.switcher = switcher
        self.notifications = notifications ?? SystemInputSourceNotificationObserver()
        self.confirmationScheduler = confirmationScheduler
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        observeNotifications()
        refresh()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        confirmationGeneration &+= 1
        confirmationScheduler.cancel()
        for token in observationTokens {
            notifications.remove(token)
        }
        observationTokens = []
        selectionFailure = nil
    }

    /// Re-reads the system. Cheap (three property reads on this Mac), so the
    /// popover may call it when it opens to cover a lost notification.
    func refresh() {
        publish(readState())
    }

    /// Selects an already-enabled input source through public TIS API.
    ///
    /// Never marks the target as current up front; the state follows the system
    /// and only the feedback text reports what happened.
    func select(id: String) {
        guard state.sources.contains(where: { $0.id == id }) else {
            selectionFailure = SelectionFailure(sourceID: id, reason: .unknownSource)
            return
        }

        selectionFailure = nil
        confirmationGeneration &+= 1
        let generation = confirmationGeneration

        switch switcher.select(id: id) {
        case let .failed(osStatus):
            selectionFailure = SelectionFailure(sourceID: id, reason: .systemRefused(osStatus: osStatus))
            refresh()
        case .selected:
            refresh()
            scheduleConfirmation(target: id, attempt: 0, generation: generation)
        }
    }

    private func observeNotifications() {
        observationTokens = [
            notifications.observe(InputSourceNotifications.selectedSourceChanged) { [weak self] in
                self?.handleSystemChange()
            },
            notifications.observe(InputSourceNotifications.enabledSourcesChanged) { [weak self] in
                self?.handleSystemChange()
            }
        ]
    }

    private func handleSystemChange() {
        guard isStarted else { return }
        refresh()
    }

    private func readState() -> InputSourceState {
        InputSourceState.resolved(
            selectedID: reader.currentKeyboardInputSourceID(),
            rawSources: reader.keyboardInputSources()
        )
    }

    private func publish(_ next: InputSourceState) {
        guard state != next else { return }
        state = next
    }

    private func scheduleConfirmation(target: String, attempt: Int, generation: Int) {
        confirmationScheduler.schedule(after: Self.confirmationInterval) { [weak self] in
            guard let self, generation == confirmationGeneration else { return }

            if reader.currentKeyboardInputSourceID() == target {
                selectionFailure = nil
                refresh()
                return
            }

            if attempt + 1 >= Self.confirmationAttempts {
                selectionFailure = SelectionFailure(sourceID: target, reason: .notConfirmed)
                refresh()
                return
            }

            scheduleConfirmation(target: target, attempt: attempt + 1, generation: generation)
        }
    }
}
