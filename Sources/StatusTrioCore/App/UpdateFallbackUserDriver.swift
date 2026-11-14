import Foundation
import Sparkle

final class UpdateFallbackUserDriver: SPUStandardUserDriver {
    var shouldSuppressUpdaterError: ((Error) -> Bool)?

    private let presentUpdaterError: ((Error, @escaping () -> Void) -> Void)?

    init(
        hostBundle: Bundle,
        delegate: SPUStandardUserDriverDelegate?,
        presentUpdaterError: ((Error, @escaping () -> Void) -> Void)? = nil
    ) {
        self.presentUpdaterError = presentUpdaterError
        super.init(hostBundle: hostBundle, delegate: delegate)
    }

    override func showUpdaterError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        if shouldSuppressUpdaterError?(error) == true {
            acknowledgement()
            return
        }

        if let presentUpdaterError {
            presentUpdaterError(error, acknowledgement)
        } else {
            UpdateFailurePresenter.present(error, acknowledgement: acknowledgement)
        }
    }
}
