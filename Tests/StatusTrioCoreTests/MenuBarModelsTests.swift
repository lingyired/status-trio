import XCTest
@testable import StatusTrioCore

final class MenuBarModelsTests: XCTestCase {
    private func contents(_ line: MenuBarLine?) -> [MenuBarElementContent] {
        line?.elements.map(\.content) ?? []
    }

    func testRoundTrip() throws {
        let instance = MenuBarInstance(
            name: "CPU",
            layoutMode: .doubleLine,
            top: MenuBarLine(elements: [MenuBarElement(content: .text("CPU ")), MenuBarElement(content: .metric(.cpuUsage))], color: .fixed(ColorValue(red: 0.2, green: 0.4, blue: 1))),
            bottom: MenuBarLine(elements: [MenuBarElement(content: .metric(.cpuTemperature))], alignment: .trailing),
            minimumWidth: 120
        )
        let config = MenuBarInstancesConfiguration(instances: [instance])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MenuBarInstancesConfiguration.self, from: data)
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.instances[0].layoutMode, .doubleLine)
    }

    func testDefaultsForNewInstance() {
        let instance = MenuBarInstance.default()
        XCTAssertEqual(instance.layoutMode, .doubleLine)
        XCTAssertEqual(instance.innerPadding, 0)
        XCTAssertEqual(instance.outerMargin, 4)
        XCTAssertEqual(instance.clickAction, .panel("summary"))
        XCTAssertEqual(instance.hoverAction, .none)
        XCTAssertEqual(contents(instance.top), [.text("CPU "), .metric(.cpuUsage)])
        XCTAssertNil(instance.bottom)
    }

    func testValidatedRejectsMoreThan20() {
        let result = MenuBarInstancesConfiguration(instances: (0..<21).map { _ in MenuBarInstance.default() }).validated()
        XCTAssertEqual(result.config.instances.count, 20)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testValidatedDropsDuplicateIDs() {
        let id = UUID()
        let a = MenuBarInstance(id: id, top: MenuBarLine(elements: [MenuBarElement(content: .metric(.cpuUsage))]))
        let b = MenuBarInstance(id: id, top: MenuBarLine(elements: [MenuBarElement(content: .metric(.gpuUsage))]))
        let result = MenuBarInstancesConfiguration(instances: [a, b]).validated()
        XCTAssertEqual(result.config.instances.count, 1)
        XCTAssertEqual(contents(result.config.instances.first?.top), [.metric(.cpuUsage)])
    }

    func testValidatedClampsPaddingAndTextLength() {
        let longText = String(repeating: "x", count: 100)
        let instance = MenuBarInstance(
            top: MenuBarLine(elements: [MenuBarElement(content: .text(longText)), MenuBarElement(content: .metric(.cpuUsage))]),
            innerPadding: 99,
            outerMargin: -3
        )
        let normalized = MenuBarInstancesConfiguration(instances: [instance]).validated().config.instances[0]
        XCTAssertEqual(normalized.innerPadding, 24)
        XCTAssertEqual(normalized.outerMargin, 0)
        guard case .text(let text)? = normalized.top?.elements.first?.content else { return XCTFail("expected text") }
        XCTAssertEqual(text.count, 64)
    }

    func testUnknownMetricDroppedFromJSON() throws {
        let config = MenuBarInstancesConfiguration(instances: [MenuBarInstance.default()])
        let json = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
            .replacingOccurrences(of: "\"cpuUsage\"", with: "\"bogusMetric\"")
        let decoded = try JSONDecoder().decode(MenuBarInstancesConfiguration.self, from: Data(json.utf8))
        XCTAssertEqual(contents(decoded.instances[0].top), [.text("CPU ")])
    }

    func testMinimumWidthValidation() {
        var instance = MenuBarInstance.default()
        instance.minimumWidth = 10
        XCTAssertEqual(MenuBarInstancesConfiguration(instances: [instance]).validated().config.instances[0].minimumWidth, 20)
        instance.minimumWidth = 999
        XCTAssertEqual(MenuBarInstancesConfiguration(instances: [instance]).validated().config.instances[0].minimumWidth, 400)
    }

    func testEmptyInstanceIsDisabledByValidation() {
        let result = MenuBarInstancesConfiguration(instances: [MenuBarInstance(top: nil, bottom: nil)]).validated()
        XCTAssertFalse(result.config.instances[0].isEnabled)
    }

    func testLegacySegmentsMigrateToElements() throws {
        let legacy = """
        {"schemaVersion":1,"instances":[{"id":"11111111-1111-1111-1111-111111111111","name":"legacy","isEnabled":true,
        "top":{"segments":[{"type":"text","text":"CPU "},{"type":"metric","metric":"cpuUsage"}]},
        "innerPadding":0,"outerMargin":4}]}
        """
        let decoded = try JSONDecoder().decode(MenuBarInstancesConfiguration.self, from: Data(legacy.utf8))
        let instance = decoded.instances[0]
        XCTAssertEqual(instance.layoutMode, .singleLine)
        XCTAssertEqual(contents(instance.top), [.text("CPU "), .metric(.cpuUsage)])
        XCTAssertFalse(instance.top?.elements[0].id == instance.top?.elements[1].id)
    }

    func testSingleLineKeepsBottomContentButDoesNotRenderIt() {
        let instance = MenuBarInstance(
            layoutMode: .singleLine,
            top: MenuBarLine(elements: [MenuBarElement(content: .metric(.cpuUsage))]),
            bottom: MenuBarLine(elements: [MenuBarElement(content: .metric(.gpuUsage))])
        )
        XCTAssertEqual(instance.renderedLines.count, 1)
        XCTAssertEqual(instance.allMetrics, [.cpuUsage])
        XCTAssertNotNil(instance.bottom)
    }
}
