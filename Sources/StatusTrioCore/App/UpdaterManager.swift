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
            self?.updateSourceFallback.canAdvanceAfterError(error) == true
        }
        return driver
    }()
    private lazy var updater = SPUUpdater(
        hostBundle: .main,
        applicationBundle: .main,
        userDriver: userDriver,
        delegate: self
    )
    private var updateSourceFallback = UpdateSourceFallback()
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

    func checkForUpdates() {
        guard AppMetadata.developmentCodename == nil else { return }
        #if DEBUG
        return
        #else
        guard canCheckForUpdates else { return }

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

        return updateSourceFallback.appcastURLString(from: directURLString)
    }

    func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with request: NSMutableURLRequest
    ) {
        guard let fileURL = item.fileURL else { return }
        request.url = updateSourceFallback.downloadURL(for: fileURL)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        if updateSourceFallback.advanceAfterError(error) {
            retryUpdateCheck(updateCheck)
            return
        }

        manualUpdatePresentation?.end()
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
