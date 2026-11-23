import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// Renders the top-app card offscreen for visual review. Skipped by default.
@MainActor
final class TopAppsSnapshotTests: XCTestCase {
    private func rows(metric: TopAppMetric) -> [TopAppRow] {
        [
            TopAppRow(id: .application(path: "/Applications/Google Chrome.app"),
                      name: "Google Chrome", applicationPath: "/Applications/Google Chrome.app",
                      value: metric == .network ? 12_400_000 : 240.5,
                      upload: metric == .network ? 1_200_000 : nil),
            TopAppRow(id: .application(path: "/Applications/Xcode.app"),
                      name: "Xcode", applicationPath: "/Applications/Xcode.app",
                      value: metric == .network ? 4_100_000 : 86.2,
                      upload: metric == .network ? 120_000 : nil),
            TopAppRow(id: .application(path: "/Applications/Microsoft Edge.app"),
                      name: "Microsoft Edge", applicationPath: "/Applications/Microsoft Edge.app",
                      value: metric == .network ? 900_000 : 41.7,
                      upload: metric == .network ? 60_000 : nil),
            TopAppRow(id: .process(ProcessIdentity(pid: 321, startedAt: 10)),
                      name: "mysteryd", applicationPath: nil,
                      value: metric == .network ? 20_000 : 12.0,
                      upload: metric == .network ? 5_000 : nil),
            TopAppRow(id: .application(path: "/Applications/Figma.app"),
                      name: "Figma", applicationPath: "/Applications/Figma.app",
                      value: metric == .network ? 10_000 : 5.4,
                      upload: metric == .network ? 1_000 : nil)
        ]
    }

    func testRenderTopAppsCard() throws {
        guard ProcessInfo.processInfo.environment["STATUS_TRIO_TOP_APPS_SNAPSHOT"] == "1" else {
            throw XCTSkip("Set STATUS_TRIO_TOP_APPS_SNAPSHOT=1 to render the top-app card")
        }
        let directory = ProcessInfo.processInfo.environment["STATUS_TRIO_TOP_APPS_SNAPSHOT_DIR"] ?? "/tmp/top_apps_snaps"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for metric in [TopAppMetric.cpu, .network] {
            for dark in [false, true] {
                let observable = TopAppsObservable()
                observable.update(.measured(metric, rows(metric: metric)))
                let view = TopAppsListView(metric: metric, observable: observable)
                    .environmentObject(Localization())
                    .environment(\.panelCardSurfaceStyle, PanelCardSurfaceStyle.material)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .frame(width: 330)
                    .background(dark ? Color(white: 0.12) : Color(white: 0.96))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let cgImage = try XCTUnwrap(renderer.cgImage)
                let rep = NSBitmapImageRep(cgImage: cgImage)
                let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                let path = "\(directory)/\(metric.rawValue)_\(dark ? "dark" : "light").png"
                try data.write(to: URL(fileURLWithPath: path))
                print("wrote \(path) (\(cgImage.width)x\(cgImage.height))")
            }
        }
    }
}
