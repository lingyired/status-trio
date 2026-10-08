import Foundation
import Testing
@testable import StatusTrioCore

struct PresentationArchitectureTests {
    @Test func sceneDoesNotDependOnSSID() {
        let base = PresentationFixtures.snapshot()
        let renamed = StatusSnapshot(
            battery: base.battery,
            wifi: WiFiStatus(state: base.wifi.state, rssi: base.wifi.rssi, ssid: "Renamed"),
            connection: base.connection,
            volume: base.volume
        )

        let baseScene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: base, audioIcon: nil),
            configuration: .standard
        )
        let renamedScene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: renamed, audioIcon: nil),
            configuration: .standard
        )

        #expect(baseScene == renamedScene)
    }

    @Test func sceneIdentityTracksWiFiBarsRatherThanRawRSSI() {
        #expect(StatusMappings.wifiBars(rssi: -62) == 2)
        #expect(StatusMappings.wifiBars(rssi: -70) == 2)
        #expect(StatusMappings.wifiBars(rssi: -60) == 3)
        #expect(StatusMappings.wifiBars(rssi: -61) == 2)

        let twoBarsA = scene(for: PresentationFixtures.snapshot(rssi: -62))
        let twoBarsB = scene(for: PresentationFixtures.snapshot(rssi: -70))
        let threeBars = scene(for: PresentationFixtures.snapshot(rssi: -60))
        #expect(twoBarsA == twoBarsB)
        #expect(twoBarsA != threeBars)
    }

    @Test func mutedRawVolumeDoesNotChangeDotsOrArcScene() {
        for style in [VolumeDisplayStyle.dots, .arc] {
            let configuration = configuration(volumeStyle: style)
            let quiet = scene(for: PresentationFixtures.snapshot(scalar: 0.1, muted: true), configuration: configuration)
            let loud = scene(for: PresentationFixtures.snapshot(scalar: 0.9, muted: true), configuration: configuration)
            #expect(quiet.footer == loud.footer)
            #expect(quiet == loud)
        }

        let arcConfiguration = configuration(volumeStyle: .arc)
        #expect(
            scene(for: PresentationFixtures.snapshot(scalar: 0.1), configuration: arcConfiguration)
                != scene(for: PresentationFixtures.snapshot(scalar: 0.9), configuration: arcConfiguration)
        )
    }

    @MainActor
    @Test func descriptiveBluetoothDeviceNameDoesNotChangeResolvedScene() {
        let original = bluetoothSnapshot(name: "AirPods", modelUID: "200f 4c")
        let renamed = bluetoothSnapshot(name: "Desk Audio", modelUID: "200f 4c")
        let originalInputs = IconPresentationResourceResolver.inputs(
            snapshot: original,
            fileExists: { _ in false },
            isSymbolAvailable: { $0 == "airpods" }
        )
        let renamedInputs = IconPresentationResourceResolver.inputs(
            snapshot: renamed,
            fileExists: { _ in false },
            isSymbolAvailable: { $0 == "airpods" }
        )
        #expect(originalInputs.audioIcon != nil)
        #expect(originalInputs.audioIcon == renamedInputs.audioIcon)

        let configuration = IconPresentationConfiguration(
            battery: .standard,
            connection: .standard,
            volume: .standard,
            bluetooth: BluetoothAudioIconOptions(replacesNetworkIcon: true)
        )
        let originalScene = IconPresentationMapper.scene(inputs: originalInputs, configuration: configuration)
        let renamedScene = IconPresentationMapper.scene(inputs: renamedInputs, configuration: configuration)
        #expect(originalScene.center == .symbol(IconSymbolState(
            source: .symbol(name: "airpods", variableValue: nil, fallback: "headphones"),
            color: .bluetooth,
            scale: BluetoothAudioIconOptions.defaultSymbolScale
        )))
        #expect(originalScene == renamedScene)
    }

    @MainActor
    @Test func accessibilityOnlySSIDAndExactVolumeDoNotChangeDotScene() {
        let first = snapshot(ssid: "Studio", scalar: 0.51)
        let second = snapshot(ssid: "Guest", scalar: 0.60)
        #expect(scene(for: first) == scene(for: second))

        let localization = Localization(preferredLanguages: ["en"])
        let firstValue = AccessibilityPresentation.statusItemValue(first, localization: localization)
        let secondValue = AccessibilityPresentation.statusItemValue(second, localization: localization)
        #expect(firstValue != secondValue)
        #expect(firstValue.contains("Studio"))
        #expect(secondValue.contains("Guest"))
    }

    @Test func rendererSourcesExcludeDomainAndStoreIdentifiers() throws {
        let renderers = [
            ("Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift", rendererForbiddenIdentifiers),
            ("Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift", rendererForbiddenIdentifiers),
            ("Sources/StatusTrioCore/App/AppIconController.swift", Set(["SystemStatusStore"]))
        ]
        for (path, forbidden) in renderers {
            let url = packageRoot.appending(path: path)
            let source = try String(contentsOf: url, encoding: .utf8)
            let found = SwiftSourceIdentifierScanner.identifiers(in: source).intersection(forbidden)
            #expect(found.isEmpty, "\(path) references forbidden identifiers: \(found.sorted())")
        }
    }

    @Test func sourceIdentifierScannerIgnoresCommentsAndLiteralTextButScansInterpolation() {
        let source = #"""
        BatteryStatus value
        // WiFiStatus
        /* outer SettingsStore /* nested SystemStatusStore */ tail */
        let plain = "VolumeStatus"
        let raw = #"NetworkConnection"#
        let longer = PrefixBatteryStatusSuffix
        let escaped = "\\(DockIconRenderer)"
        let interpolated = "text \(SettingsStore.shared)"
        """#
        let identifiers = SwiftSourceIdentifierScanner.identifiers(in: source)
        #expect(identifiers.contains("BatteryStatus"))
        #expect(identifiers.contains("SettingsStore"))
        #expect(!identifiers.contains("WiFiStatus"))
        #expect(!identifiers.contains("VolumeStatus"))
        #expect(!identifiers.contains("NetworkConnection"))
        #expect(!identifiers.contains("SystemStatusStore"))
        #expect(!SwiftSourceIdentifierScanner.identifiers(in: "PrefixBatteryStatusSuffix").contains("BatteryStatus"))
        #expect(!identifiers.contains("DockIconRenderer"))

        let nested = #"let text = "\(String(describing: "inner") + SettingsStore.description)""#
        let raw = ##"let text = #"\\#(SettingsStore.shared)"#"##
        #expect(SwiftSourceIdentifierScanner.identifiers(in: nested).contains("SettingsStore"))
        #expect(SwiftSourceIdentifierScanner.identifiers(in: raw).contains("SettingsStore"))
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var rendererForbiddenIdentifiers: Set<String> {
        [
            "BatteryStatus", "WiFiStatus", "VolumeStatus", "NetworkConnection",
            "SystemStatusStore", "SettingsStore", "IconPresentationMapper"
        ]
    }

    private func scene(
        for snapshot: StatusSnapshot,
        configuration: IconPresentationConfiguration = .standard
    ) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: configuration
        )
    }

    private func configuration(volumeStyle: VolumeDisplayStyle) -> IconPresentationConfiguration {
        IconPresentationConfiguration(
            battery: .standard,
            connection: .standard,
            volume: VolumeIconOptions(
                displayStyle: volumeStyle,
                ringStrokeScale: VolumeIconOptions.standard.ringStrokeScale
            ),
            bluetooth: .standard
        )
    }

    private func snapshot(ssid: String, scalar: Double) -> StatusSnapshot {
        let base = PresentationFixtures.snapshot(scalar: scalar)
        return StatusSnapshot(
            battery: base.battery,
            wifi: WiFiStatus(state: base.wifi.state, rssi: base.wifi.rssi, ssid: ssid),
            connection: base.connection,
            volume: base.volume
        )
    }

    private func bluetoothSnapshot(name: String, modelUID: String) -> StatusSnapshot {
        let device = AudioOutputDevice(
            id: 7,
            name: name,
            uid: "fixture-bluetooth-output",
            isCurrent: true,
            volume: 0.5,
            transport: .bluetooth,
            modelUID: modelUID
        )
        return StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -62),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: name, currentDevice: device)
        )
    }
}
