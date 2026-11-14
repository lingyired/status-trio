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

    /// Raw appcast URL from Info.plist, before mirroring. Injectable so a test
    /// can exercise the delegate path without depending on `Bundle.main`.
    var directFeedURLString: () -> String? = {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        currentProxiedFeedURLString()
    }

    /// Mirrors the raw appcast URL through the active update source. Kept
    /// internal so a test can prove this path still adds the mirror prefix.
    func currentProxiedFeedURLString() -> String? {
        guard let directURLString = directFeedURLString() else { return nil }

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
        if advanceUpdateSource(after: error) {
            retryUpdateCheck(updateCheck)
            return
        }

        manualUpdatePresentation?.end()
    }

    /// Advances the mirror after a retryable error; returns false when the round
    /// ends. Internal so tests can drive the same path the delegate uses.
    @discardableResult
    func advanceUpdateSource(after error: Error?) -> Bool {
        updateSourceFallback.advanceAfterError(error)
    }

    /// Returns the fallback to the primary source; internal for tests that
    /// advance it and must not leak state into other cases.
    func restoreInitialUpdateSource() {
        updateSourceFallback = UpdateSourceFallback()
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
