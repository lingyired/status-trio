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
        instance.top = MenuBarLine(elements: [])
        store.updateMenuBarInstance(instance)
        return (MenuBarInstanceEditorModel(instance: instance, store: store), store)
    }

    private func contents(_ model: MenuBarInstanceEditorModel, _ slot: MenuBarLineSlot) -> [MenuBarElementContent] {
        model.elements(slot: slot).map(\.content)
    }

    func testAddElementsOrder() {
        let (model, _) = makeModel()
        model.addTextElement("CPU ", slot: .top)
        model.addMetricElement(.cpuUsage, slot: .top)
        XCTAssertEqual(contents(model, .top), [.text("CPU "), .metric(.cpuUsage)])
    }

    func testMoveElement() {
        let (model, _) = makeModel()
        model.addTextElement("A", slot: .top)
        let id = model.addMetricElement(.cpuUsage, slot: .top)!
        model.moveElement(id: id, to: 0, slot: .top)
        XCTAssertEqual(contents(model, .top), [.metric(.cpuUsage), .text("A")])
    }

    func testRemoveElement() {
        let (model, _) = makeModel()
        let id = model.addTextElement("A", slot: .top)!
        model.addTextElement("B", slot: .top)
        model.removeElement(id: id, slot: .top)
        XCTAssertEqual(contents(model, .top), [.text("B")])
    }

    func testMoveElementAcrossLines() {
        let (model, _) = makeModel()
        let id = model.addMetricElement(.cpuUsage, slot: .top)!
        model.moveElement(id: id, from: .top, to: .bottom)
        XCTAssertEqual(contents(model, .top), [])
        XCTAssertEqual(contents(model, .bottom), [.metric(.cpuUsage)])
    }

    func testIconElement() {
        let (model, _) = makeModel()
        model.addIconElement(MenuBarIconSpec(source: .emoji("🔥")), slot: .top)
        guard case .icon? = model.elements(slot: .top).first?.content else { return XCTFail("expected icon") }
    }

    func testEditorKeepsVisibilityChangedFromTheList() {
        let (model, store) = makeModel()
        var latest = store.menuBarInstances.instances[0]
        latest.isEnabled = false
        store.updateMenuBarInstance(latest)

        model.addTextElement("CPU ", slot: .top)

        XCTAssertFalse(store.menuBarInstances.instances[0].isEnabled)
    }

    func testPreviewUsesRenderer() {
        let (model, _) = makeModel()
        model.addMetricElement(.cpuUsage, slot: .top)
        XCTAssertNotNil(model.previewImage())
    }

    func testEditWritesStore() {
        let (model, store) = makeModel()
        model.addTextElement("X", slot: .top)
        XCTAssertEqual(store.menuBarInstances.instances.first?.top?.elements.map(\.content), [.text("X")])
    }

    func testPaddingClamped() {
        let (model, _) = makeModel()
        model.setPadding(inner: 99, outer: -5)
        XCTAssertEqual(model.instance.innerPadding, 24)
        XCTAssertEqual(model.instance.outerMargin, 0)
    }

    func testLayoutModeSwitchKeepsBottom() {
        let (model, _) = makeModel()
        model.addMetricElement(.gpuUsage, slot: .bottom)
        model.setLayoutMode(.doubleLine)
        model.setLayoutMode(.singleLine)
        XCTAssertNotNil(model.instance.bottom)
        XCTAssertEqual(contents(model, .bottom), [.metric(.gpuUsage)])
    }
}
