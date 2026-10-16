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

        if let savedPreference = settings.savedLowPowerModeControlPreference {
            helper.restoreUserIntent(savedPreference)
        }

        // Mirror the user's opt-in into the persisted flag. It follows the
        // switch, not the raw system status: a registration macOS has not
        // approved yet is still what the user asked for, and the switch must not
        // flicker with the status while the app waits for that approval.
        helper.$isEnabled
            .removeDuplicates()
            .sink { [weak settings] isEnabled in
                guard let settings, settings.controlsLowPowerMode != isEnabled else { return }
                settings.controlsLowPowerMode = isEnabled
            }
            .store(in: &cancellables)

        // Approval happens in System Settings, so re-read the status when the app
        // comes back to the foreground. Without this, a registration approved
        // while the app was in the background keeps showing "waiting for
        // approval" until the Settings window is closed and reopened.
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
