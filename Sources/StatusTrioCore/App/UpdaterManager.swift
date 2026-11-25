import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class UpdaterManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdaterManager()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false

    private lazy var userDriver: UpdateFallbackUserDriver = {
        let driver = UpdateFallbackUserDriver(hostBundle: .main, delegate: nil)
        driver.shouldSuppressUpdaterError = { [weak self] error in
            self?.updateCycle.canSuppressErrorForRetry(error) == true
        }
        return driver
    }()
    private lazy var updater = SPUUpdater(
        hostBundle: .main,
        applicationBundle: .main,
        userDriver: userDriver,
        delegate: self
    )
    private var updateCycle = UpdateCycleState()
    private var manualUpdatePresentation: ManualUpdatePresentation?

    /// Injectable full-screen probe. Tests replace it to exercise the gate
    /// without a real full-screen Space.
    var isFullScreenActive: @MainActor () -> Bool = { FullScreenActivity.isActive() }
    private var fullScreenMonitor: FullScreenActivityMonitor?
    /// Set when a scheduled check is postponed because another app owns the
    /// screen; cleared when the postponed check is finally run.
    private var didPostponeScheduledCheckForFullScreen = false

    var automaticallyChecksForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { self.automaticallyChecksForUpdates },
            set: { self.updater.automaticallyChecksForUpdates = $0 }
        )
    }

    private override init() {
        super.init()

        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func start(activationPolicy: AppActivationPolicy) {
        manualUpdatePresentation = ManualUpdatePresentation(
            activationPolicy: activationPolicy
        )
        guard AppMetadata.developmentCodename == nil else { return }
        #if DEBUG
        return
        #else
        do {
            try updater.start()
        } catch {
            NSAlert(error: error).runModal()
        }
        startFullScreenMonitor()
        #endif
    }

    func checkForUpdates(preference: UpdatePreference = .githubFirst) {
        guard AppMetadata.developmentCodename == nil else { return }
        #if DEBUG
        return
        #else
        guard canCheckForUpdates, updateCycle.beginManual(preference: preference) else { return }

        manualUpdatePresentation?.begin()
        updater.checkForUpdates()
        #endif
    }

    /// Defers only background (scheduled) checks while another app owns the
    /// screen; a check the user asked for must still run.
    ///
    /// Throwing aborts the check before Sparkle fetches the appcast or shows
    /// any alert. Sparkle suppresses updater errors that happen before an
    /// update was presented, so the deferral is silent. The postponed check is
    /// re-run when the full-screen session ends.
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard shouldDeferUpdateCheck(updateCheck) else {
            if updateCheck == .updatesInBackground {
                didPostponeScheduledCheckForFullScreen = false
            }
            return
        }
        didPostponeScheduledCheckForFullScreen = true
        throw Self.fullScreenPostponementError()
    }

    /// Pure decision shared by the delegate and tests.
    func shouldDeferUpdateCheck(_ updateCheck: SPUUpdateCheck) -> Bool {
        updateCheck == .updatesInBackground && isFullScreenActive()
    }

    private func startFullScreenMonitor() {
        let monitor = FullScreenActivityMonitor(
            probe: { [weak self] in self?.isFullScreenActive() ?? false }
        )
        monitor.onExitFullScreen = { [weak self] in
            self?.resumePostponedScheduledCheck()
        }
        monitor.start()
        fullScreenMonitor = monitor
    }

    private func resumePostponedScheduledCheck() {
        guard didPostponeScheduledCheckForFullScreen else { return }
        guard !isFullScreenActive() else { return }
        didPostponeScheduledCheckForFullScreen = false
        guard automaticallyChecksForUpdates, canCheckForUpdates else { return }
        updater.checkForUpdatesInBackground()
    }

    private static func fullScreenPostponementError() -> NSError {
        NSError(
            domain: "com.lingsmbp.StatusTrio.Updater",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Update check postponed while another app is in full screen.",
            ]
        )
    }

    /// Raw appcast URL from Info.plist, before mirroring. Injectable for tests.
    var directFeedURLString: () -> String? = {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        if !updateCycle.isActive {
            _ = updateCycle.beginAutomaticIfIdle()
        }
        return currentProxiedFeedURLString()
    }

    func currentProxiedFeedURLString() -> String? {
        guard let directURLString = directFeedURLString() else { return nil }
        return updateCycle.appcastURLString(from: directURLString)
    }

    @discardableResult
    func advanceUpdateSource(after error: Error?) -> Bool {
        let advanced = updateCycle.advanceForTest(error)
        if !advanced { updateCycle.resetForTest() }
        return advanced
    }

    func restoreInitialUpdateSource() {
        updateCycle.resetForTest()
    }

    func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with request: NSMutableURLRequest
    ) {
        guard let fileURL = item.fileURL else { return }
        updateCycle.markDownloading()
        request.url = updateCycle.downloadURL(for: fileURL)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        updateCycle.prepareForRetryAfterFinishedCycle()
        if updateCycle.advanceAfterError(error) {
            retryUpdateCheck(updateCheck)
            return
        }

        let giteeMayLag = updateCycle.isGiteeFirstCycle && Self.isNoUpdateError(error)
        updateCycle.finish()
        manualUpdatePresentation?.end()
        if giteeMayLag {
            presentGiteeMirrorMayLagAlert()
        }
    }

    private static func isNoUpdateError(_ error: Error?) -> Bool {
        guard let nsError = error as NSError? else { return false }
        if nsError.domain == SUSparkleErrorDomain,
           nsError.code == Int(SUError.noUpdateError.rawValue) {
            return true
        }
        guard let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error else { return false }
        return isNoUpdateError(underlying)
    }

    private func presentGiteeMirrorMayLagAlert() {
        let localization = Localization()
        let alert = NSAlert()
        alert.messageText = localization.string(.settingsUpdatesGiteeLaggingTitle)
        alert.informativeText = localization.string(.settingsUpdatesGiteeLaggingMessage)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        updateCycle.markInstalling()
    }

    private func retryUpdateCheck(_ updateCheck: SPUUpdateCheck) {
        switch updateCheck {
        case .updates:
            updater.checkForUpdates()
        case .updatesInBackground:
            updater.checkForUpdatesInBackground()
        default:
            break
        }
    }
}
