import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct UpdateFailureRecoveryTests {
    @Test(arguments: AppLanguage.allCases)
    func failureCopyIsLocalizedForEveryLanguage(_ language: AppLanguage) {
        let suite = "UpdateFailureRecoveryTests.\(UUID().uuidString)"
        defer { TestUserDefaults.removeSuite(named: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("system", forKey: Localization.defaultsKey)
        let localization = Localization(defaults: defaults, preferredLanguages: [language.rawValue])
        let recovery = UpdateFailureRecovery(error: URLError(.timedOut), localization: localization)

        #expect(recovery.title != "updates.failure.title")
        #expect(recovery.message.contains(URLError(.timedOut).localizedDescription))
        #expect(recovery.message.contains("DMG"))
        #expect(recovery.buttonTitles.count == 2)
        #expect(recovery.downloadURL(forButton: 0)?.absoluteString == "https://statustrio.lingai.net/")
        #expect(recovery.downloadURL(forButton: 1) == nil)
        #expect(recovery.downloadURL(forButton: recovery.buttonTitles.count - 1) == nil)
        #expect(recovery.downloadURL(forButton: -1) == nil)
        #expect(recovery.downloadURL(forButton: 99) == nil)
    }

    @Test
    func manualAppLanguageControlsCopyEvenWhenSystemIsEnglish() {
        let suite = "UpdateFailureRecoveryTests.\(UUID().uuidString)"
        defer { TestUserDefaults.removeSuite(named: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("system", forKey: Localization.defaultsKey)
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.simplifiedChinese))
        let recovery = UpdateFailureRecovery(error: URLError(.timedOut), localization: localization)

        #expect(recovery.title == "更新失败")
        #expect(recovery.buttonTitles == ["官网下载", "取消"])
        #expect(recovery.message.contains("最新 DMG"))
        #expect(recovery.message.contains("官网提供的网盘"))
    }

    @Test(arguments: [0, 1, 2, -1])
    func selectedDownloadOpensOnceThenAcknowledges(_ selectedButton: Int) {
        let suite = "UpdateFailureRecoveryTests.\(UUID().uuidString)"
        defer { TestUserDefaults.removeSuite(named: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("system", forKey: Localization.defaultsKey)
        let localization = Localization(defaults: defaults, preferredLanguages: ["zh-Hans"])
        var events: [String] = []
        var openedURLs: [URL] = []
        UpdateFailurePresenter.present(
            URLError(.timedOut),
            acknowledgement: { events.append("acknowledged") },
            localization: localization,
            runDialog: { recovery in
                #expect(recovery.buttonTitles.count == 2)
                events.append("dialog")
                return selectedButton
            },
            openURL: { url in
                events.append("opened")
                openedURLs.append(url)
            }
        )

        if selectedButton == 0 {
            #expect(events == ["dialog", "opened", "acknowledged"])
            #expect(openedURLs.count == 1)
            #expect(openedURLs.first?.host == "statustrio.lingai.net")
        } else {
            #expect(events == ["dialog", "acknowledged"])
            #expect(openedURLs.isEmpty)
        }
    }
}
