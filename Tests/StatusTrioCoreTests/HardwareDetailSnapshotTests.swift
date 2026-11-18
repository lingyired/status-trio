import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// Renders all five detail pages offscreen (light + dark) to PNG so the layout
/// can be reviewed without opening a window. Skipped unless explicitly enabled.
@MainActor
final class HardwareDetailSnapshotTests: XCTestCase {
    private func now() -> Date { Date() }

    private func snapshot(for kind: HardwareDetailKind, at date: Date) -> HardwareMetricsSnapshot {
        var snapshot = HardwareMetricsSnapshot.empty
        switch kind {
        case .cpu:
            let kinds = Array(repeating: CPUCoreKind.efficiency, count: 4)
                + Array(repeating: .performance, count: 12)
            snapshot.cpuDetail = CPUDetailReading(
                usage: 26.4,
                breakdown: CPUTimeBreakdown(user: 15.2, system: 4.1, idle: 79.6, nice: 1.1),
                perCoreUsage: [8, 12, 15, 9, 22, 28, 31, 26, 35, 40, 33, 29, 24, 38, 30, 27],
                topology: CPUCoreTopology(kinds: kinds),
                groupUsage: CPUCoreGroupUsage(efficiencyAverage: 11, performanceAverage: 29.6, superAverage: nil, otherAverage: nil),
                frequency: CPUFrequencyReading(efficiencyGHz: 1.94, performanceGHz: 2.41, superGHz: nil, sampledAt: date),
                sampledAt: date)
            snapshot.samples[.cpuUsage] = HardwareMetricSample(value: 26.4, unit: .percent, sampledAt: date, source: .mach, availability: .measured)
            snapshot.samples[.cpuTemperature] = HardwareMetricSample(value: 46, unit: .celsius, sampledAt: date, source: .smc, availability: .measured)
        case .gpu:
            snapshot.gpuDetail = GPUDetailReading(deviceName: "Apple M3 Max", usage: 37,
                                                  rendererUtilization: 42, tilerUtilization: 35,
                                                  inUseSystemMemoryBytes: 4_200_000_000, sampledAt: date)
            snapshot.samples[.gpuUsage] = HardwareMetricSample(value: 37, unit: .percent, sampledAt: date, source: .ioAccelerator, availability: .measured)
            snapshot.samples[.gpuTemperature] = HardwareMetricSample(value: 52, unit: .celsius, sampledAt: date, source: .smc, availability: .measured)
        case .memory:
            snapshot.memoryDetail = MemoryDetailReading(percent: 44.5, usedBytes: 61_000_000_000,
                                                        totalBytes: 137_400_000_000, appBytes: 52_600_000_000,
                                                        wiredBytes: 8_000_000_000, compressedBytes: 400_000_000,
                                                        cachedBytes: 37_500_000_000, swapUsedBytes: 0,
                                                        swapTotalBytes: 0, pressure: .normal, sampledAt: date)
            snapshot.samples[.memoryUsage] = HardwareMetricSample(value: 44.5, unit: .percent, sampledAt: date, source: .mach, availability: .measured)
        case .network:
            snapshot.networkDetail = NetworkDetailReading(downloadBytesPerSecond: 12_400_000,
                                                          uploadBytesPerSecond: 1_100_000,
                                                          sessionReceivedBytes: 3_400_000_000,
                                                          sessionSentBytes: 240_000_000,
                                                          interfaces: ["en0"], sampledAt: date)
            snapshot.samples[.networkDownload] = HardwareMetricSample(value: 12_400_000, unit: .bytesPerSecond, sampledAt: date, source: .mach, availability: .measured)
            snapshot.samples[.networkUpload] = HardwareMetricSample(value: 1_100_000, unit: .bytesPerSecond, sampledAt: date, source: .mach, availability: .measured)
        case .disk:
            snapshot.diskDetail = DiskDetailReading(
                capacity: DiskCapacityReading(totalBytes: 1_995_000_000_000, freeBytes: 533_000_000_000,
                                              usedBytes: 1_462_000_000_000, fileSystem: "APFS", sampledAt: date),
                readBytesPerSecond: 45_000_000, writeBytesPerSecond: 12_000_000, sampledAt: date)
            snapshot.samples[.diskRead] = HardwareMetricSample(value: 45_000_000, unit: .bytesPerSecond, sampledAt: date, source: .ioStorage, availability: .measured)
            snapshot.samples[.diskWrite] = HardwareMetricSample(value: 12_000_000, unit: .bytesPerSecond, sampledAt: date, source: .ioStorage, availability: .measured)
        }
        return snapshot
    }

    private func history(for kind: HardwareDetailKind, at date: Date) -> [HardwareDetailHistoryPoint] {
        let series = kind.historySeriesCount
        return (0..<30).map { index in
            let pointDate = date.addingTimeInterval(-60 + Double(index) * 2)
            let phase = Double(index) / 3.6
            let values: [Double?]
            switch kind {
            case .cpu, .gpu:
                values = [26 + 14 * sin(phase)]
            case .memory:
                values = [45 + 8 * sin(phase)]
            case .network:
                values = [12_000_000 + 9_000_000 * sin(phase), 1_000_000 + 700_000 * cos(phase)]
            case .disk:
                values = [40_000_000 + 25_000_000 * sin(phase), 10_000_000 + 8_000_000 * cos(phase)]
            }
            return HardwareDetailHistoryPoint(id: index, date: pointDate, values: Array(values.prefix(series)))
        }
    }

    func testRenderAllDetailPagesLightAndDark() throws {
        guard ProcessInfo.processInfo.environment["STATUS_TRIO_DETAIL_SNAPSHOT"] == "1" else {
            throw XCTSkip("Set STATUS_TRIO_DETAIL_SNAPSHOT=1 to render detail pages")
        }
        let directory = ProcessInfo.processInfo.environment["STATUS_TRIO_DETAIL_SNAPSHOT_DIR"] ?? "/tmp/detail_snaps"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let date = now()
        for kind in HardwareDetailKind.allCases {
            let snap = snapshot(for: kind, at: date)
            let points = history(for: kind, at: date)
            for dark in [false, true] {
                let observable = HardwareMonitorObservable(snapshot: snap)
                let view = HardwareDetailView(kind: kind, hardware: observable, onBack: {}, previewHistory: points)
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
                let path = "\(directory)/\(kind.rawValue)_\(dark ? "dark" : "light").png"
                try data.write(to: URL(fileURLWithPath: path))
                print("wrote \(path) (\(cgImage.width)x\(cgImage.height))")
            }
        }
    }
}
