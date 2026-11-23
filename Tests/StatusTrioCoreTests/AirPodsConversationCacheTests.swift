import XCTest
@testable import StatusTrioCore

final class AirPodsConversationCacheTests: XCTestCase {
    @MainActor
    func testRouteChangesInvalidateAndRejectLateResults() {
        let cache = AirPodsConversationCache()
        let route = PanelAudioDeviceID(id: 42, uid: "first")
        cache.updateRoute(route)
        let generation = cache.generation
        let options = [AirPodsSystemOption(title: "On", selected: true)]
        cache.store(options, route: route, generation: generation)
        XCTAssertEqual(cache.options(for: route), options)
        cache.updateRoute(PanelAudioDeviceID(id: 43, uid: "second"))
        XCTAssertTrue(cache.options(for: route).isEmpty)
        cache.updateRoute(nil)
        cache.updateRoute(route)
        cache.store(options, route: route, generation: generation)
        XCTAssertTrue(cache.options(for: route).isEmpty)
    }

    @MainActor
    func testPartialRefreshPreservesCachedConversationThenReplacesIt() async throws {
        let cache = AirPodsConversationCache()
        let route = PanelAudioDeviceID(id: 42, uid: "first")
        cache.updateRoute(route)
        let old = [AirPodsSystemOption(title: "On", selected: true)]
        cache.store(old, route: route, generation: cache.generation)
        let model = AirPodsSystemControlsModel(deviceID: route, deviceName: "AirPods", conversationCache: cache)
        XCTAssertEqual(model.snapshot.conversation, old)
        var finish: CheckedContinuation<Void, Never>?
        model.refresh { _, publish in
            publish(.init(spatialLoaded: true))
            await withCheckedContinuation { finish = $0 }
            return .init(conversation: [], loaded: true, conversationLoaded: true)
        }
        for _ in 0..<100 where finish == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(finish)
        XCTAssertEqual(model.snapshot.conversation, old)
        finish?.resume()
        for _ in 0..<100 where model.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(model.snapshot.conversation.isEmpty)
        XCTAssertTrue(cache.options(for: route).isEmpty)
        model.stop()
    }
    @MainActor
    func testConfirmedRefreshSurvivesModelRecreationButFailedWriteClearsCache() async throws {
        let cache = AirPodsConversationCache()
        let route = PanelAudioDeviceID(id: 42, uid: "first")
        cache.updateRoute(route)
        let options = [AirPodsSystemOption(title: "Off", selected: true)]
        let model = AirPodsSystemControlsModel(deviceID: route, deviceName: "AirPods", conversationCache: cache)
        XCTAssertTrue(model.snapshot.conversation.isEmpty)
        model.refresh { _, _ in .init(conversation: options, loaded: true, conversationLoaded: true) }
        for _ in 0..<100 where model.busy { try await Task.sleep(for: .milliseconds(5)) }
        model.stop()
        let reopened = AirPodsSystemControlsModel(deviceID: route, deviceName: "AirPods", conversationCache: cache)
        XCTAssertEqual(reopened.snapshot.conversation, options)
        reopened.run(.option(.conversation)) { throw AirPodsSystemControlError.unconfirmed }
        for _ in 0..<100 where reopened.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(cache.options(for: route).isEmpty)
        XCTAssertTrue(reopened.snapshot.conversation.isEmpty)
        reopened.stop()
    }

}
