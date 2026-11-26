import XCTest
@testable import StatusTrioCore

final class MenuBarModelsTests: XCTestCase {
    func testRoundTrip() throws {
        let instance = MenuBarInstance(
            name: "CPU",
            top: MenuBarLine(segments: [.text("CPU "), .metric(.cpuUsage)], color: .fixed(ColorValue(red: 0.2, green: 0.4, blue: 1))),
            bottom: MenuBarLine(segments: [.metric(.cpuTemperature)], alignment: .trailing)
        )
        let config = MenuBarInstancesConfiguration(instances: [instance])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MenuBarInstancesConfiguration.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testDefaultsForNewInstance() {
        let instance = MenuBarInstance.default()
        XCTAssertEqual(instance.innerPadding, 0)
        XCTAssertEqual(instance.outerMargin, 4)
        XCTAssertEqual(instance.clickAction, .panel("summary"))
        XCTAssertEqual(instance.hoverAction, .none)
        XCTAssertEqual(instance.rightClick, .sameAsMainIcon)
        XCTAssertTrue(instance.isEnabled)
        XCTAssertEqual(instance.top?.segments.count, 2)
        XCTAssertNil(instance.bottom)
    }

    func testValidatedRejectsMoreThan20() {
        let instances = (0..<21).map { _ in MenuBarInstance.default() }
        let result = MenuBarInstancesConfiguration(instances: instances).validated()
        XCTAssertEqual(result.config.instances.count, 20)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testValidatedDropsDuplicateIDs() {
        let id = UUID()
        let a = MenuBarInstance(id: id, top: MenuBarLine(segments: [.metric(.cpuUsage)]))
        let b = MenuBarInstance(id: id, top: MenuBarLine(segments: [.metric(.gpuUsage)]))
        let result = MenuBarInstancesConfiguration(instances: [a, b]).validated()
        XCTAssertEqual(result.config.instances.count, 1)
        XCTAssertEqual(result.config.instances.first?.top?.segments, [.metric(.cpuUsage)])
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testValidatedClampsPaddingAndTextLength() {
        let longText = String(repeating: "x", count: 100)
        let instance = MenuBarInstance(
            top: MenuBarLine(segments: [.text(longText), .metric(.cpuUsage)]),
            innerPadding: 99,
            outerMargin: -3
        )
        let result = MenuBarInstancesConfiguration(instances: [instance]).validated()
        let normalized = result.config.instances[0]
        XCTAssertEqual(normalized.innerPadding, 24)
        XCTAssertEqual(normalized.outerMargin, 0)
        guard case .text(let text)? = normalized.top?.segments.first else {
            return XCTFail("expected text segment")
        }
        XCTAssertEqual(text.count, 64)
    }

    func testUnknownMetricDroppedFromJSON() throws {
        let config = MenuBarInstancesConfiguration(instances: [MenuBarInstance.default()])
        let data = try JSONEncoder().encode(config)
        let json = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\"cpuUsage\"", with: "\"bogusMetric\"")
        let corrupted = Data(json.utf8)
        let decoded = try JSONDecoder().decode(MenuBarInstancesConfiguration.self, from: corrupted)
        // Only the text segment survives; the unknown metric segment is dropped.
        XCTAssertEqual(decoded.instances[0].top?.segments.count, 1)
        XCTAssertEqual(decoded.instances[0].top?.segments, [.text("CPU ")])
    }

    func testEmptyInstanceIsDisabledByValidation() {
        let instance = MenuBarInstance(top: nil, bottom: nil)
        let result = MenuBarInstancesConfiguration(instances: [instance]).validated()
        XCTAssertFalse(result.config.instances[0].isEnabled)
    }
}
