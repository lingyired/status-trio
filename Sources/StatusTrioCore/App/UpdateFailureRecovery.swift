import AppKit
import Foundation

@MainActor
struct UpdateFailureRecovery {
    private static let websiteURL = AppMetadata.projectHomepageURL

    let title: String
    let message: String
    let buttonTitles: [String]

    init(error: Error, localization: Localization) {
        title = localization.string(.updateFailureTitle)
        message = localization.string(.updateFailureMessage) + "\n\n" + error.localizedDescription
        buttonTitles = [
            localization.string(.updateFailureWebsite),
            localization.string(.commonCancel)
        ]
    }

    func downloadURL(forButton index: Int) -> URL? {
        index == 0 ? Self.websiteURL : nil
    }
}

@MainActor
enum UpdateFailurePresenter {
    static func present(
        _ error: Error,
        acknowledgement: () -> Void,
        localization: Localization? = nil,
        runDialog: ((UpdateFailureRecovery) -> Int)? = nil,
        openURL: ((URL) -> Void)? = nil
    ) {
        defer { acknowledgement() }
        let recovery = UpdateFailureRecovery(error: error, localization: localization ?? Localization())
        let selectedButton: Int
        if let runDialog {
            selectedButton = runDialog(recovery)
        } else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = recovery.title
            alert.informativeText = recovery.message
            for title in recovery.buttonTitles {
                alert.addButton(withTitle: title)
            }
            alert.buttons.last?.keyEquivalent = "\u{1b}"
            selectedButton = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        }
        guard let url = recovery.downloadURL(forButton: selectedButton) else { return }
        if let openURL {
            openURL(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
