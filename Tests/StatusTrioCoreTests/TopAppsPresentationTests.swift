import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class TopAppsPresentationTests: XCTestCase {
    private func renderedHeight(_ view: some View) throws -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: 330))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        return CGFloat(image.height)
    }

    private func localization(_ language: String) -> Localization {
        let suite = "TopAppsPresentationTests.\(UUID().uuidString)"
        return Localization(defaults: UserDefaults(suiteName: suite)!,
                            preferredLanguages: [language])
    }

    func testApplicationPercentIsNotClamped() {
        XCTAssertEqual(HardwareDetailFormat.appPercent(240.5), "240.5%")
        XCTAssertEqual(HardwareDetailFormat.appPercent(0), "0.0%")
        XCTAssertEqual(HardwareDetailFormat.appPercent(-1), HardwareDetailFormat.dash)
    }

    func testNetworkAndStateFormatting() {
        XCTAssertEqual(HardwareDetailFormat.rate(2_048), "2 KB/s")
        XCTAssertEqual(HardwareDetailFormat.rate(1_500_000), "1.5 MB/s")
        XCTAssertNotEqual(HardwareDetailFormat.bytes(1_610_612_736), HardwareDetailFormat.dash)
    }

    func testLongNamesRTLAndLargeValuesKeepFiveRowsReachable() throws {
        let rows = (0..<5).map { index in
            TopAppRow(id: .application(path: "/Applications/Very Long Application Name \(index).app"),
                      name: "Very Long Application Name \(index) — A Helper That Should Truncate",
                      applicationPath: "/Applications/Very Long Application Name \(index).app",
                      value: Double(240.5 - Double(index)),
                      upload: nil)
        }
        let observable = TopAppsObservable()
        observable.update(.measured(.cpu, rows))
        let full = TopAppsListView(metric: .cpu, observable: observable)
            .environmentObject(localization("en"))

        let emptyObservable = TopAppsObservable()
        emptyObservable.update(.measured(.cpu, []))
        let empty = TopAppsListView(metric: .cpu, observable: emptyObservable)
            .environmentObject(localization("en"))

        let fullHeight = try renderedHeight(full)
        let emptyHeight = try renderedHeight(empty)
        XCTAssertGreaterThan(fullHeight, emptyHeight + 40)

        let arabic = TopAppsListView(metric: .cpu, observable: observable)
            .environmentObject(localization("ar"))
        XCTAssertNotNil(try? XCTUnwrap(ImageRenderer(content: arabic.frame(width: 330)).cgImage))
    }

    func testAllPresentationStatesRender() throws {
        let states: [TopAppsState] = [
            .idle,
            .collecting(.gpu),
            .measured(.gpu, []),
            .unsupported(.gpu),
            .failed(.gpu)
        ]
        for (index, state) in states.enumerated() {
            let observable = TopAppsObservable()
            observable.update(state)
            let view = TopAppsListView(metric: .gpu, observable: observable)
                .environmentObject(localization(index == 0 ? "en" : "zh-Hans"))
            XCTAssertNotNil(try? XCTUnwrap(ImageRenderer(content: view.frame(width: 330)).cgImage))
        }
    }
}
