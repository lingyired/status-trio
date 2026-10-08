import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusMenuBuilderTests: XCTestCase {
    func testMenuContainsLocalizedVersionSettingsAndQuit() {
        let localization = makeLocalization(.simplifiedChinese)
        let menu = StatusMenuBuilder.makeMenu(
            version: "1.0.0",
            settingsTarget: nil,
            settingsAction: nil,
            localization: localization
        )
        let versionItem = menu.items[0]
        let settingsItem = menu.items[1]
        let quitItem = menu.items[3]

        XCTAssertEqual(menu.items.map(\.title), [
            "Status Trio 1.0.0",
            "设置…",
            "",
            "退出 Status Trio"
        ])
        XCTAssertFalse(versionItem.isEnabled)
        XCTAssertFalse(settingsItem.isEnabled)
        XCTAssertTrue(quitItem.isEnabled)
        XCTAssertEqual(quitItem.keyEquivalent, "q")
        XCTAssertEqual(quitItem.keyEquivalentModifierMask, .command)
        XCTAssertTrue(quitItem.target === NSApplication.shared)
        XCTAssertEqual(quitItem.action, #selector(NSApplication.terminate(_:)))
        XCTAssertEqual(menu.userInterfaceLayoutDirection, .leftToRight)
    }

    func testGermanMenuUsesSelectedLanguage() {
        let localization = makeLocalization(.german)
        let menu = StatusMenuBuilder.makeMenu(
            version: "1.0.0",
            settingsTarget: nil,
            settingsAction: nil,
            localization: localization
        )

        XCTAssertEqual(menu.items.map(\.title), [
            "Status Trio 1.0.0",
            "Einstellungen…",
            "",
            "Status Trio beenden"
        ])
    }

    func testArabicMenuUsesRightToLeftLayout() {
        let localization = makeLocalization(.arabic)
        let menu = StatusMenuBuilder.makeMenu(
            version: "1.0.0",
            settingsTarget: nil,
            settingsAction: nil,
            localization: localization
        )

        XCTAssertEqual(menu.userInterfaceLayoutDirection, .rightToLeft)
    }

    func testSettingsItemUsesProvidedTargetAndAction() {
        let target = SettingsTarget()
        let menu = StatusMenuBuilder.makeMenu(
            version: "1.0.0",
            settingsTarget: target,
            settingsAction: #selector(SettingsTarget.openSettings),
            localization: makeLocalization(.simplifiedChinese)
        )
        let settingsItem = menu.items[1]

        XCTAssertTrue(settingsItem.isEnabled)
        XCTAssertTrue(settingsItem.target === target)
        XCTAssertEqual(settingsItem.action, #selector(SettingsTarget.openSettings))
    }

    private final class SettingsTarget: NSObject {
        @objc func openSettings() {}
    }

    func testClickClassification() {
        XCTAssertEqual(StatusBarController.clickKind(eventType: .leftMouseUp, modifiers: []), .left)
        XCTAssertEqual(StatusBarController.clickKind(eventType: .rightMouseUp, modifiers: []), .right)
        XCTAssertEqual(StatusBarController.clickKind(eventType: .leftMouseUp, modifiers: [.control]), .right)
        XCTAssertNil(StatusBarController.clickKind(eventType: .leftMouseDown, modifiers: []))
        XCTAssertNil(StatusBarController.clickKind(eventType: .flagsChanged, modifiers: []))
    }

    func testSystemSettingsURLFallbackOrder() {
        // The Wi-Fi route must come first on every supported macOS version: the
        // Network pane lists services, not networks, and System Settings still
        // reports success for it, so a wrong first route is never corrected by
        // the fallbacks. This assertion is the guard against the 1.2.0/1.3.0
        // regression, where a majorVersion >= 27 branch demoted the Wi-Fi route
        // and sent macOS 15 through 26 to the Network pane.
        XCTAssertEqual(
            StatusBarController.wifiSettingsURLs.map(\.absoluteString),
            [
                "x-apple.systempreferences:com.apple.wifi-settings-extension",
                "x-apple.systempreferences:com.apple.Network-Settings.extension?Wi-Fi",
                "x-apple.systempreferences:com.apple.preference.network?Wi-Fi"
            ]
        )
        XCTAssertEqual(
            StatusBarController.locationSettingsURLs.map(\.absoluteString),
            [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
            ]
        )
        XCTAssertEqual(
            StatusBarController.batterySettingsURLs.map(\.absoluteString),
            [
                "x-apple.systempreferences:com.apple.Battery-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.battery"
            ]
        )
        // Two different panes: the gear turns the radio on and off, while the
        // row's refused-grant action belongs in Privacy & Security.
        XCTAssertEqual(
            StatusBarController.bluetoothSettingsURLs.map(\.absoluteString),
            [
                "x-apple.systempreferences:com.apple.BluetoothSettings",
                "x-apple.systempreferences:com.apple.preference.bluetooth"
            ]
        )
        XCTAssertEqual(
            SystemStatusStore.bluetoothPermissionSettingsURLs.map(\.absoluteString),
            [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Bluetooth",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
            ]
        )
    }

    private func makeLocalization(_ language: AppLanguage) -> Localization {
        let suiteName = "StatusTrioCoreTests.StatusMenuBuilder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removeTestSuite(named: suiteName)
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        return localization
    }
}
