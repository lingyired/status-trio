import XCTest
@testable import StatusTrioCore

final class SettingsPagesOptimizationContractTests: XCTestCase {
    func testDeviceSettingsPagesUseCompactMenuBarOnlyPreview() throws {
        let root = projectRoot
        let pages = [
            "BatterySectionView.swift",
            "NetworkSectionView.swift",
            "BluetoothSectionView.swift",
            "AudioSectionView.swift"
        ]

        for file in pages {
            let page = try source("Sources/StatusTrioCore/UI/Settings/\(file)", root: root)
            XCTAssertTrue(page.contains("content: .menuBarOnly"), "\(file) must use the compact menu-bar-only preview.")
        }
    }

    func testDevicePagesExposeSourceBehaviorWithoutDuplicatingDesignerAppearanceControls() throws {
        let root = projectRoot
        let battery = try source("Sources/StatusTrioCore/UI/Settings/BatterySectionView.swift", root: root)
        let network = try source("Sources/StatusTrioCore/UI/Settings/NetworkSectionView.swift", root: root)
        let bluetooth = try source("Sources/StatusTrioCore/UI/Settings/BluetoothSectionView.swift", root: root)
        let audio = try source("Sources/StatusTrioCore/UI/Settings/AudioSectionView.swift", root: root)
        let appearance = try source("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconAppearanceEditor.swift", root: root)

        XCTAssertTrue(battery.contains("$store.showsBatteryPercentage"))
        XCTAssertTrue(battery.contains("$store.showsChargingIndicator"))
        XCTAssertTrue(battery.contains(".settingsBatteryMacBehavior"), "Battery controls must be labeled as Mac battery behavior because AirPods can be the primary ring source.")
        XCTAssertTrue(network.contains("$store.showsWiFiIconForEthernet"))
        XCTAssertTrue(network.contains("$store.showsWiFiIconForHotspot"))
        XCTAssertTrue(network.contains("$store.showsWiFiIconForTemporaryConnection"))
        XCTAssertTrue(network.contains("$store.showsWiFiIconForInternetSharing"))
        XCTAssertFalse(battery.contains("batterySymbolScale"), "Sizing belongs in Icon Designer.")
        XCTAssertFalse(network.contains("wifiSymbolScale"), "Wi-Fi scale must remain a single control in Appearance.")
        XCTAssertTrue(appearance.contains(".iconDesignerControlSymbolScale"), "The Wi-Fi scale remains part of the designer Appearance controls.")

        XCTAssertTrue(bluetooth.contains("store.prioritizesNetworkErrorsOverBluetoothAudio"))
        XCTAssertTrue(audio.contains("$store.volumeDisplayStyle"))
        XCTAssertTrue(bluetooth.contains("deviceOrderGroup"), "Bluetooth device management must remain available.")
        XCTAssertTrue(audio.contains("deviceOrderGroup"), "Audio output ordering must remain available.")
    }

    func testLegacyShortcutsAreConditionalOnSelectedCenterSource() throws {
        let network = try source("Sources/StatusTrioCore/UI/Settings/NetworkSectionView.swift", root: projectRoot)
        let bluetooth = try source("Sources/StatusTrioCore/UI/Settings/BluetoothSectionView.swift", root: projectRoot)
        XCTAssertTrue(network.contains("if store.iconConfiguration.composition.center.primary == .automaticLegacy {"))
        XCTAssertTrue(bluetooth.contains("if primary == .automaticLegacy || primary == .bluetoothAudioOutput {"))
        XCTAssertTrue(bluetooth.contains("if store.iconConfiguration.composition.center.primary == .automaticLegacy {"))
        XCTAssertTrue(bluetooth.contains("networkProblemOverridesPrimary = value"))
    }

    func testEachDevicePageRoutesToItsDesignerSlotWithoutEditingStoredConfiguration() throws {
        let root = projectRoot
        let settings = try source("Sources/StatusTrioCore/UI/Settings/SettingsView.swift", root: root)
        let designer = try source("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerView.swift", root: root)
        let appEnvironment = try source("Sources/StatusTrioCore/App/AppEnvironment.swift", root: root)
        let designerController = try source("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerWindowController.swift", root: root)
        let settingsController = try source("Sources/StatusTrioCore/UI/Settings/SettingsWindowController.swift", root: root)
        let pageTargets: [(String, String)] = [
            ("BatterySectionView.swift", ".outerRing"),
            ("NetworkSectionView.swift", ".center"),
            ("BluetoothSectionView.swift", ".center"),
            ("AudioSectionView.swift", ".footer")
        ]

        for (file, slot) in pageTargets {
            let page = try source("Sources/StatusTrioCore/UI/Settings/\(file)", root: root)
            XCTAssertTrue(page.contains("onOpenIconDesigner(\(slot))"), "\(file) must request its corresponding transient designer slot.")
        }
        XCTAssertTrue(settings.contains("onOpenIconDesigner: onOpenIconDesigner"))
        XCTAssertTrue(appEnvironment.contains("openIconDesigner: { [weak iconDesignerWindowController] slot in"))
        XCTAssertTrue(appEnvironment.contains("iconDesignerWindowController?.show(slot: slot)"))
        XCTAssertTrue(appEnvironment.contains("let iconDesignerPreviewSession = IconDesignerPreviewSession()"))
        XCTAssertTrue(appEnvironment.contains("previewSession: iconDesignerPreviewSession"))
        XCTAssertTrue(designerController.contains("let previewSession: IconDesignerPreviewSession"))
        XCTAssertTrue(designerController.contains("func show(slot: IconSlot = .outerRing)"))
        XCTAssertTrue(designerController.contains("previewSession.selectedSlot = slot"), "The requested slot is transient shared-session state.")
        XCTAssertTrue(settingsController.contains("previewSession: previewSession"))
        XCTAssertFalse(designer.contains("store.updateIconConfiguration"), "Opening the floating designer must not rewrite configuration.")
    }

    func testIconSettingsUsesIndependentDesignerEntryAndPreservesDisplaySettings() throws {
        let settings = try source("Sources/StatusTrioCore/UI/Settings/SettingsView.swift", root: projectRoot)
        let section = try source("Sources/StatusTrioCore/UI/Settings/IconDesignerLaunchSectionView.swift", root: projectRoot)
        let iconCase = try XCTUnwrap(settings.range(of: "case .iconDesigner:"))
        let followingCase = try XCTUnwrap(settings[iconCase.upperBound...].range(of: "case .battery:"))
        let iconBranch = String(settings[iconCase.lowerBound..<followingCase.lowerBound])

        XCTAssertTrue(iconBranch.contains("IconDesignerLaunchSectionView("))
        XCTAssertFalse(iconBranch.contains("IconDesignerView("), "Ordinary settings must not embed the large designer.")
        XCTAssertTrue(section.contains("IconDesignerEntryRow("))
        XCTAssertTrue(section.contains("onOpenIconDesigner(.outerRing)"))
        XCTAssertTrue(section.contains("IconSurfaceSettings("), "Placement, menu-bar size, and Dock appearance controls must remain.")
        XCTAssertTrue(section.contains("onShowIconGuide"), "The existing icon guide action must remain available.")
        XCTAssertFalse(section.contains("store.updateIconConfiguration"), "Opening the designer must not persist icon changes.")
    }

    @MainActor
    func testQuickControlsWriteThroughToCanonicalIconBehaviors() {
        let suiteName = "SettingsPagesOptimizationContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        let compositionBefore = store.iconConfiguration.composition
        store.showsBatteryPercentageInConnectionSlot = true
        store.showsBatteryPercentage = false
        store.showsChargingIndicator = false
        store.showsWiFiIconForEthernet = true
        store.showsWiFiIconForHotspot = false
        store.prioritizesNetworkErrorsOverBluetoothAudio = true
        store.volumeDisplayStyle = .arc

        XCTAssertFalse(store.iconConfiguration.behaviors.systemBatteryRing.showsPercentage)
        XCTAssertFalse(store.iconConfiguration.behaviors.systemBatteryRing.showsChargingIndicator)
        XCTAssertTrue(store.iconConfiguration.behaviors.networkCenter.showsWiFiIconForEthernet)
        XCTAssertFalse(store.iconConfiguration.behaviors.networkCenter.showsWiFiIconForHotspot)
        XCTAssertTrue(store.iconConfiguration.behaviors.bluetoothAudioCenter.prioritizesNetworkErrors)
        XCTAssertEqual(store.iconConfiguration.behaviors.systemVolumeFooter.displayStyle, .arc)
        XCTAssertTrue(store.iconConfiguration.behaviors.networkCenter.showsBatteryPercentageInConnectionSlot)
        XCTAssertEqual(store.iconConfiguration.composition, compositionBefore)
    }

    @MainActor
    func testBluetoothPriorityBindingEditsOnlyRelevantCanonicalPolicyWithoutChangingSources() {
        let suiteName = "SettingsPagesPriorityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)

        for primary in CenterSource.allCases {
            store.updateIconConfiguration {
                $0.composition.center.primary = primary
                $0.behaviors.bluetoothAudioCenter.prioritizesNetworkErrors = false
                $0.composition.centerOverride.networkProblemOverridesPrimary = false
            }
            let before = store.iconConfiguration
            let binding = BluetoothSectionView.networkErrorPriorityBinding(store: store)
            XCTAssertFalse(binding.wrappedValue)
            binding.wrappedValue = true

            var expected = before
            switch primary {
            case .automaticLegacy:
                expected.behaviors.bluetoothAudioCenter.prioritizesNetworkErrors = true
            case .bluetoothAudioOutput:
                expected.composition.centerOverride.networkProblemOverridesPrimary = true
            default:
                break
            }
            XCTAssertEqual(store.iconConfiguration, expected, "Wrong priority mapping for \(primary)")
            XCTAssertEqual(store.iconConfiguration.composition.center, before.composition.center)
            XCTAssertEqual(binding.wrappedValue, primary == .automaticLegacy || primary == .bluetoothAudioOutput)
            XCTAssertEqual(SettingsStore(defaults: defaults).iconConfiguration, expected)
        }
    }

    func testDesignerEntryUsesLocalizedContextualCopyAndNativeSettingsGroup() throws {
        let root = projectRoot
        let entry = try source("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerEntryRow.swift", root: root)
        XCTAssertTrue(entry.contains("SettingsGroup"))
        XCTAssertFalse(entry.contains("SettingsGroup(\"Icon settings\")"))
        XCTAssertFalse(entry.contains("Configure in Icon Designer"))
        let pages = try [
            "Sources/StatusTrioCore/UI/Settings/BatterySectionView.swift",
            "Sources/StatusTrioCore/UI/Settings/NetworkSectionView.swift",
            "Sources/StatusTrioCore/UI/Settings/BluetoothSectionView.swift",
            "Sources/StatusTrioCore/UI/Settings/AudioSectionView.swift"
        ].map { try source($0, root: root) }.joined(separator: "\n")
        for key in ["settingsBatteryDesignerEntry", "settingsNetworkDesignerEntry", "settingsBluetoothDesignerEntry", "settingsAudioDesignerEntry"] {
            XCTAssertTrue(pages.contains(".\(key)"), "Missing contextual localized entry: \(key)")
        }
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String, root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
