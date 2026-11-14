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

    func feedURLString(for updater: SPUUpdater) -> String? {
        guard
            let directURLString = Bundle.main.object(
                forInfoDictionaryKey: "SUFeedURL"
            ) as? String
        else {
            return nil
        }

        if !updateCycle.isActive {
            _ = updateCycle.beginAutomaticIfIdle()
        }
        return updateCycle.appcastURLString(from: directURLString)
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
