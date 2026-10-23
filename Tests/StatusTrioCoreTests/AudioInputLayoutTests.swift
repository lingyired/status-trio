import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class AudioInputLayoutTests: XCTestCase {
    func testBusyStateKeepsInputControlsAtTheSameSize() throws {
        for language in [AppLanguage.english, .simplifiedChinese, .german, .arabic] {
            let idle = try size(busy: false, language: language)
            let busy = try size(busy: true, language: language)
            XCTAssertEqual(idle.width, busy.width, accuracy: 0.1, language.rawValue)
            XCTAssertEqual(idle.height, busy.height, accuracy: 0.1, language.rawValue)
        }
    }

    private func size(busy: Bool, language: AppLanguage) throws -> NSSize {
        let suite = "AudioInputLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: [language.rawValue])
        let device = AudioInputDevice(id: 11, uid: "layout-mic", name: "Studio AirPods Pro")
        let status = AudioInputStatus(
            devices: [device],
            defaultDeviceID: device.id,
            deviceName: device.name,
            scalar: 0.5,
            canSetVolume: true,
            muteState: .unmuted,
            canSetMute: true,
            isRefreshing: false,
            isBusy: busy,
            error: nil
        )
        let host = NSHostingView(rootView:
            AudioInputControlsView(
                state: AudioPanelMapper.input(status, localization: localization),
                actions: StatusPanelActions(),
                onOpenSoundSettings: {}
            )
            .padding(14)
            .frame(width: 330)
            .environmentObject(localization)
            .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
        )
        return host.fittingSize
    }
}
