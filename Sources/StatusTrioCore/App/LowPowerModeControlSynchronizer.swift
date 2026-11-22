import AppKit
import Combine

/// Persists the feature opt-in independently of helper registration.
///
/// The persisted opt-in records user intent; the manager separately observes
/// system approval. Keeping a registered helper must not re-enable a feature
/// the user disabled when the app is relaunched.
@MainActor
final class LowPowerModeControlSynchronizer {
    private var cancellables = Set<AnyCancellable>()
    private var activationObserver: NSObjectProtocol?

    func start(settings: SettingsStore, helper: PrivilegedHelperManager) {
        guard cancellables.isEmpty, activationObserver == nil else { return }

        // The helper is shared by two independent consumer intents: the battery
        // power controls and the lid-sleep toggle. It stays enabled while EITHER
        // is on and is only disabled when the user turns both off — never because
        // a panel section is hidden. This replaces the old one-way mirror where
        // the helper switch and the low-power-mode control were the same state.
        Publishers.CombineLatest(
            settings.$controlsLowPowerMode,
            settings.$showsLidSleepButton
        )
        .map { $0 || $1 }
        .removeDuplicates()
        .sink { [weak helper] desired in
            guard let helper, helper.isEnabled != desired else { return }
            helper.setEnabled(desired)
        }
        .store(in: &cancellables)

        // Forward activation so the manager can complete the one-shot return
        // from Login Items. Ordinary foreground changes don't query the system.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak helper] _ in
            Task { @MainActor in helper?.refreshAfterActivation() }
        }
    }

    func stop() {
        cancellables.removeAll()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }
}
