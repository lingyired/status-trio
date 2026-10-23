import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class MenuBarHelpLocalizationTests: XCTestCase {
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "MenuBarHelpLocalizationTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    func testEveryMenuBarHelpKeyLoadsInEveryLanguage() {
        let keys = MenuBarHelpPolicy.allLocalizationKeys

        for language in AppLanguage.allCases {
            let (defaults, suiteName) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let localization = Localization(
                defaults: defaults,
                preferredLanguages: [language.rawValue]
            )

            for key in keys {
                let value = localization.string(key)
                XCTAssertFalse(
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(language.rawValue): \(key.rawValue) is empty"
                )
                XCTAssertNotEqual(
                    value,
                    key.rawValue,
                    "\(language.rawValue): \(key.rawValue) is not translated"
                )
            }
        }
    }

    func testLongAndRightToLeftHelpLayoutsKeepAFixedPopoverSize() {
        for language in [
            AppLanguage.english,
            .simplifiedChinese,
            .traditionalChinese,
            .german,
            .arabic
        ] {
            let (defaults, suiteName) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let localization = Localization(
                defaults: defaults,
                preferredLanguages: [language.rawValue]
            )
            let view = MenuBarVisibilityHelpView(
                policy: MenuBarHelpPolicy(majorVersion: 26),
                onClose: {},
                openSettings: { _ in }
            )
            .environmentObject(localization)
            .environment(\.layoutDirection, language.layoutDirection)

            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 372)
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertEqual(hostingView.fittingSize.width, 480, accuracy: 1)
            XCTAssertEqual(hostingView.fittingSize.height, 372, accuracy: 1)
        }
    }
}
