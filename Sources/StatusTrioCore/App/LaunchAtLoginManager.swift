import Combine
import ServiceManagement
import SwiftUI

/// The app's login item registration as reported by the system.
enum LaunchAtLoginStatus: Equatable, Sendable {
    /// The app doesn't launch at login.
    ///
    /// macOS reports an app that has never registered as `notRegistered` on some
    /// versions and `notFound` on others, so both collapse into this case.
    case notRegistered
    /// The app is registered and launches at login.
    case enabled
    /// Registered, but macOS needs the user to approve it in Login Items.
    case requiresApproval
}

/// Abstracts `SMAppService` so the manager can be exercised with a fake.
@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    /// False when the process doesn't run from an app bundle, where macOS cannot
    /// manage a login item at all — for example under `swift run`.
    var isSupported: Bool { get }
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openLoginItemsSettings()
}

@MainActor
final class SystemLaunchAtLoginService: LaunchAtLoginServicing {
    var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    var status: LaunchAtLoginStatus {
        Self.status(for: SMAppService.mainApp.status)
    }

    /// `SMAppService` answers `notFound` for an app that has never registered a
    /// login item, which is the same situation as `notRegistered` for our UI.
    /// Registering still works from that state, so it must not disable the toggle.
    static func status(for status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notRegistered, .notFound:
            .notRegistered
        @unknown default:
            .notRegistered
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Keeps the login item registration in sync with the user's preference and
/// republishes the system state so the settings UI can react to it.
@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var status: LaunchAtLoginStatus
    @Published private(set) var didFailLastOperation = false

    private let service: LaunchAtLoginServicing

    /// The opt-in value whose last attempt failed.
    ///
    /// Approval happens in System Settings, so the state the failed call wanted
    /// can arrive later without any further action in the app. Remembering what
    /// was attempted lets `refresh()` drop the error once the system catches up
    /// instead of leaving the failure banner on screen until the user happens to
    /// touch the toggle again.
    private var failedOperationTarget: Bool?

    init(service: LaunchAtLoginServicing = SystemLaunchAtLoginService()) {
        self.service = service
        self.status = service.status
    }

    /// A registration that still awaits approval counts as on, so the toggle
    /// keeps showing what the user asked for instead of silently flipping back.
    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    /// False when macOS cannot manage a login item for this process.
    var isAvailable: Bool {
        service.isSupported
    }

    var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.isEnabled },
            set: { self.setEnabled($0) }
        )
    }

    func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        didFailLastOperation = false
        failedOperationTarget = nil

        do {
            if enabled {
                if !isEnabled {
                    try service.register()
                }
            } else if isEnabled {
                try service.unregister()
            }
        } catch {
            didFailLastOperation = true
            failedOperationTarget = enabled
        }

        refresh()
    }

    /// Re-reads the system state and retires a failure the system has since
    /// satisfied. `requiresApproval` is not enough to retire a failed
    /// registration: a rejected `register()` leaves the item in exactly that
    /// state, so the banner stays until the item is really `.enabled`. A failed
    /// unregister is settled by the item disappearing.
    func refresh() {
        status = service.status

        guard let target = failedOperationTarget else { return }
        let satisfied = target ? status == .enabled : status == .notRegistered
        guard satisfied else { return }

        failedOperationTarget = nil
        didFailLastOperation = false
    }

    func openLoginItemsSettings() {
        service.openLoginItemsSettings()
    }
}
