import XCTest
@testable import StatusTrioCore

final class MenuBarInstanceTransferTests: XCTestCase {
    private func makeInstance() -> MenuBarInstance {
        var instance = MenuBarInstance(
            name: "Network",
            layoutMode: .doubleLine,
            top: MenuBarLine(
                elements: [MenuBarElement(content: .metric(.networkUpload))],
                leadingIcon: MenuBarIconSpec(source: .sfSymbol("arrow.up")),
                leadingIconSize: 14,
                leadingIconColor: ColorValue(red: 0.2, green: 0.6, blue: 1),
                color: .fixed(ColorValue(red: 0.9, green: 0.2, blue: 0.2)),
                alignment: .trailing
            ),
            bottom: MenuBarLine(elements: [MenuBarElement(content: .metric(.networkDownload))]),
            innerPadding: 3,
            minimumWidth: 120
        )
        instance.isEnabled = false
        return instance
    }

    func testRoundTripPreservesInstance() throws {
        let original = makeInstance()
        let data = try MenuBarInstanceTransfer.encode(original)
        let decoded = try MenuBarInstanceTransfer.decode(data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.layoutMode, original.layoutMode)
        XCTAssertEqual(decoded.isEnabled, original.isEnabled)
        XCTAssertEqual(decoded.innerPadding, original.innerPadding)
        XCTAssertEqual(decoded.minimumWidth, original.minimumWidth)
        XCTAssertEqual(decoded.top?.leadingIcon, original.top?.leadingIcon)
        XCTAssertEqual(decoded.top?.leadingIconSize, 14)
        XCTAssertEqual(decoded.top?.leadingIconColor, original.top?.leadingIconColor)
        XCTAssertEqual(decoded.top?.color, original.top?.color)
        XCTAssertEqual(decoded.top?.alignment, .trailing)
    }

    func testElementColorRoundTrips() throws {
        var instance = MenuBarInstance(name: "Colored")
        instance.top = MenuBarLine(elements: [
            MenuBarElement(content: .metric(.cpuUsage),
                           color: .fixed(ColorValue(red: 0.2, green: 0.4, blue: 0.9)))
        ])
        let decoded = try MenuBarInstanceTransfer.decode(
            MenuBarInstanceTransfer.encode(instance)
        )
        XCTAssertEqual(decoded.top?.elements.first?.color,
                       .fixed(ColorValue(red: 0.2, green: 0.4, blue: 0.9)))
    }

    func testBatchRoundTripPreservesOrderAndCount() throws {
        let a = MenuBarInstance(name: "CPU", top: MenuBarLine(elements: [MenuBarElement(content: .metric(.cpuUsage))]))
        let b = MenuBarInstance(name: "Memory", top: MenuBarLine(elements: [MenuBarElement(content: .metric(.memoryUsage))]))
        let data = try MenuBarInstanceTransfer.encodeAll([a, b])
        let decoded = try MenuBarInstanceTransfer.decodeAll(data)
        XCTAssertEqual(decoded.map(\.name), ["CPU", "Memory"])
        XCTAssertEqual(decoded.map(\.id), [a.id, b.id])
    }

    func testBatchDecodeAcceptsBareInstanceArray() throws {
        let a = MenuBarInstance(name: "CPU")
        let b = MenuBarInstance(name: "GPU")
        let data = try JSONEncoder().encode([a, b])
        let decoded = try MenuBarInstanceTransfer.decodeAll(data)
        XCTAssertEqual(decoded.map(\.name), ["CPU", "GPU"])
    }

    func testBatchDecodeAcceptsSingleInstanceDocument() throws {
        let original = makeInstance()
        let data = try MenuBarInstanceTransfer.encode(original)
        let decoded = try MenuBarInstanceTransfer.decodeAll(data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.name, original.name)
    }

    func testDecodesBareInstanceJSON() throws {
        let original = MenuBarInstance(name: "CPU", top: MenuBarLine(elements: [MenuBarElement(content: .text("CPU"))]))
        let data = try JSONEncoder().encode(original)
        let decoded = try MenuBarInstanceTransfer.decode(data)
        XCTAssertEqual(decoded.name, "CPU")
        XCTAssertEqual(decoded.top?.elements, original.top?.elements)
    }

    func testRejectsMalformedData() {
        XCTAssertThrowsError(try MenuBarInstanceTransfer.decode(Data("not json".utf8)))
    }
}
