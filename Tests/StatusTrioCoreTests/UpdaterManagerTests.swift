import Combine
import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct UpdaterManagerTests {
    @Test
    func settingAutomaticallyChecksForUpdatesPublishesChange() {
        let manager = UpdaterManager.shared
        let originalValue = manager.automaticallyChecksForUpdates
        defer {
            manager.automaticallyChecksForUpdatesBinding.wrappedValue = originalValue
        }

        var didPublishChange = false
        let cancellable = manager.objectWillChange.sink {
            didPublishChange = true
        }
        defer { cancellable.cancel() }

        manager.automaticallyChecksForUpdatesBinding.wrappedValue = !originalValue

        #expect(didPublishChange)
        #expect(manager.automaticallyChecksForUpdates == !originalValue)
    }

    @Test
    func feedURLStringMirrorsThroughActiveSourceAndResets() {
        let manager = UpdaterManager.shared
        let originalProvider = manager.directFeedURLString
        defer {
            manager.directFeedURLString = originalProvider
            manager.restoreInitialUpdateSource()
        }

        let direct = "https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml"
        manager.directFeedURLString = { direct }
        manager.restoreInitialUpdateSource()

        #expect(manager.currentProxiedFeedURLString() == direct)

        let toProxy = manager.advanceUpdateSource(after: URLError(.timedOut))
        #expect(toProxy)
        #expect(
            manager.currentProxiedFeedURLString()
                == "https://gh-proxy.com/" + direct
        )

        let toGhFast = manager.advanceUpdateSource(after: URLError(.timedOut))
        #expect(toGhFast)
        #expect(
            manager.currentProxiedFeedURLString()
                == "https://ghfast.top/" + direct
        )

        let pastGhFast = manager.advanceUpdateSource(after: URLError(.timedOut))
        #expect(!pastGhFast)
        #expect(manager.currentProxiedFeedURLString() == direct)
    }

    @Test
    func feedURLStringIsNilWhenInfoPlistHasNoFeed() {
        let manager = UpdaterManager.shared
        let originalProvider = manager.directFeedURLString
        defer { manager.directFeedURLString = originalProvider }

        manager.directFeedURLString = { nil }

        #expect(manager.currentProxiedFeedURLString() == nil)
    }
}
