import AppKit
import SwiftUI
import Testing
@testable import StatusTrioCore

@MainActor
struct DockIconPreviewGuideTests {
    /// The guide shows 10 states (`IconGuideState.all`) at 44 pt
    /// (`Sources/StatusTrioCore/UI/IconGuideView.swift:541-550`) and the
    /// appearance picker re-renders all of them. Each card may rasterize at most
    /// once per (state, appearance), and revisiting the guide must rasterize
    /// nothing: before this task every hosting pass rendered all 20 again.
    @Test func revisitingTheGuideRendersNothingNew() throws {
        let suiteName = "StatusTrioCoreTests.DockIconPreviewGuide.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { TestUserDefaults.removeSuite(named: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(
            defaults: defaults,
            preferredLanguages: [AppLanguage.english.rawValue]
        )
        var renderedLengths: [Int] = []
        let cache = DockIconPreviewCache(limit: 64) {
            renderedLengths.append($0)
        }
        let cardCount = IconGuideState.all.count
            * IconGuidePreviewAppearance.allCases.count
        var firstPassCount = 0

        for pass in 0..<2 {
            for appearance in IconGuidePreviewAppearance.allCases {
                for state in IconGuideState.all {
                    let card = IconGuideStateCard(
                        state: state,
                        settings: settings,
                        previewAppearance: appearance,
                        previewCache: cache
                    )
                    .environmentObject(localization)
                    let hostingView = NSHostingView(rootView: card)
                    hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 120)
                    hostingView.layoutSubtreeIfNeeded()
                    _ = hostingView.fittingSize
                }
            }

            if pass == 0 {
                firstPassCount = renderedLengths.count
            }
        }

        #expect(cardCount == 20)
        #expect(firstPassCount >= 1)
        #expect(firstPassCount <= cardCount)
        #expect(
            renderedLengths.count == firstPassCount,
            "The second visit to the guide must reuse every raster."
        )
        #expect(renderedLengths.allSatisfy { $0 == 112 })
    }
}
