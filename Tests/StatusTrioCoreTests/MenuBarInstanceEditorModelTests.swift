import XCTest
@testable import StatusTrioCore

@MainActor
final class MenuBarInstanceEditorModelTests: XCTestCase {
    private func scratchStore() -> SettingsStore {
        let suite = "menubar.editor.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: defaults)
    }

    private func makeModel() -> (MenuBarInstanceEditorModel, SettingsStore) {
        let store = scratchStore()
        var instance = MenuBarInstance(name: "t")
        instance.top = MenuBarLine(segments: [])
        store.updateMenuBarInstance(instance)
        return (MenuBarInstanceEditorModel(instance: instance, store: store), store)
    }

    func testAddMetricSegmentOrder() {
        let (model, _) = makeModel()
        model.addTextSegment("CPU ", slot: .top)
        model.addMetricSegment(.cpuUsage, slot: .top)
        XCTAssertEqual(model.instance.top?.segments, [.text("CPU "), .metric(.cpuUsage)])
    }

    func testMoveSegment() {
        let (model, _) = makeModel()
        model.addTextSegment("A", slot: .top)
        model.addMetricSegment(.cpuUsage, slot: .top)
        model.moveSegment(from: 1, to: 0, slot: .top)
        XCTAssertEqual(model.instance.top?.segments, [.metric(.cpuUsage), .text("A")])
    }

    func testRemoveSegment() {
        let (model, _) = makeModel()
        model.addTextSegment("A", slot: .top)
        model.addTextSegment("B", slot: .top)
        model.removeSegment(at: 0, slot: .top)
        XCTAssertEqual(model.instance.top?.segments, [.text("B")])
    }

    func testPreviewUsesRenderer() {
        let (model, _) = makeModel()
        model.addMetricSegment(.cpuUsage, slot: .top)
        XCTAssertNotNil(model.previewImage())
    }

    func testEditWritesStore() {
        let (model, store) = makeModel()
        model.addTextSegment("X", slot: .top)
        XCTAssertEqual(store.menuBarInstances.instances.first?.top?.segments, [.text("X")])
    }

    func testPaddingClamped() {
        let (model, _) = makeModel()
        model.setPadding(inner: 99, outer: -5)
        XCTAssertEqual(model.instance.innerPadding, 24)
        XCTAssertEqual(model.instance.outerMargin, 0)
    }
}
