import Foundation
import Testing
@testable import StatusTrioCore

struct TopAppAggregationTests {
    private func metadata(pid: Int32, name: String = "Process",
                          path: String? = nil, responsible: Int32? = nil,
                          startedAt: UInt64 = 1) -> ProcessMetadata {
        ProcessMetadata(identity: ProcessIdentity(pid: pid, startedAt: startedAt),
                        name: name, executablePath: path, responsiblePID: responsible)
    }

    private func application(pid: Int32, path: String, name: String) -> ProcessApplication {
        ProcessApplication(pid: pid, path: path, bundleID: "bundle.\(pid)", name: name)
    }

    @Test func testMergeBeforeTakingFive() {
        var applications: [ProcessApplication] = []
        var samples: [ProcessUsageSample] = []
        for index in 0..<6 {
            let pid = Int32(100 + index)
            applications.append(application(pid: pid, path: "/Applications/App\(index).app", name: "App\(index)"))
            samples.append(ProcessUsageSample(metadata: metadata(pid: pid, name: "App\(index)"), value: 9))
        }
        applications.append(application(pid: 500, path: "/Applications/Chrome.app", name: "Chrome"))
        for index in 0..<3 {
            let pid = Int32(501 + index)
            samples.append(ProcessUsageSample(
                metadata: metadata(pid: pid, name: "Chrome Helper",
                                   path: "/Applications/Chrome.app/Contents/Frameworks/Chrome Helper.app/Contents/MacOS/Chrome Helper",
                                   responsible: 500),
                value: 4
            ))
        }

        let rows = TopAppAggregator.rows(metric: .cpu, samples: samples, applications: applications)
        #expect(rows.count == 5)
        #expect(rows.first?.name == "Chrome")
        #expect(rows.first?.value == 12)
        #expect(rows.first?.applicationPath == "/Applications/Chrome.app")
    }

    @Test func testNestedHelpersAndSameNameDifferentPaths() {
        let applications = [
            application(pid: 100, path: "/Applications/A.app", name: "Same Name"),
            application(pid: 200, path: "/Applications/B.app", name: "Same Name")
        ]
        let samples = [
            ProcessUsageSample(metadata: metadata(pid: 100, name: "Same Name"), value: 5),
            ProcessUsageSample(metadata: metadata(pid: 200, name: "Same Name"), value: 7),
            ProcessUsageSample(
                metadata: metadata(pid: 101, name: "Same Name Helper",
                                   path: "/Applications/A.app/Contents/Frameworks/Same Name Helper.app/Contents/MacOS/Same Name Helper",
                                   responsible: 100),
                value: 3
            )
        ]

        let rows = TopAppAggregator.rows(metric: .cpu, samples: samples, applications: applications)
        #expect(rows.count == 2)
        #expect(rows.map(\.name) == ["Same Name", "Same Name"])
        #expect(rows.map(\.value) == [8, 7])
        #expect(Set(rows.compactMap(\.applicationPath)).count == 2)
    }

    @Test func testInvalidOwnerFallsBackToPathThenProcess() {
        let applications = [application(pid: 100, path: "/Applications/A.app", name: "A")]
        let pathFallback = ProcessUsageSample(
            metadata: metadata(pid: 300, name: "C Helper",
                               path: "/Applications/C.app/Contents/MacOS/C Helper",
                               responsible: -1),
            value: 4
        )
        let processFallback = ProcessUsageSample(
            metadata: metadata(pid: 400, name: "mysteryd", path: nil, responsible: 0),
            value: 3
        )

        let rows = TopAppAggregator.rows(metric: .cpu,
                                         samples: [pathFallback, processFallback],
                                         applications: applications)
        #expect(rows.count == 2)
        #expect(rows[0].name == "C")
        #expect(rows[0].applicationPath == "/Applications/C.app")
        #expect(rows[1].name == "mysteryd")
        #expect(rows[1].applicationPath == nil)
    }

    @Test func testNetworkSortUsesBusiestDirection() {
        let applications = [
            application(pid: 1, path: "/Applications/Downloader.app", name: "Downloader"),
            application(pid: 2, path: "/Applications/Uploader.app", name: "Uploader"),
            application(pid: 3, path: "/Applications/Balanced.app", name: "Balanced")
        ]
        let samples = [
            ProcessUsageSample(metadata: metadata(pid: 1), value: 80, upload: 0),
            ProcessUsageSample(metadata: metadata(pid: 2), value: 0, upload: 60),
            ProcessUsageSample(metadata: metadata(pid: 3), value: 50, upload: 50)
        ]

        let rows = TopAppAggregator.rows(metric: .network, samples: samples, applications: applications)
        #expect(rows.map(\.name) == ["Downloader", "Uploader", "Balanced"])
        #expect(rows[0].upload == 0)
    }

    @Test func testZeroNegativeAndNonFiniteAreSkipped() {
        let applications = [
            application(pid: 1, path: "/Applications/A.app", name: "A"),
            application(pid: 2, path: "/Applications/B.app", name: "B")
        ]
        let samples = [
            ProcessUsageSample(metadata: metadata(pid: 1), value: 0),
            ProcessUsageSample(metadata: metadata(pid: 2), value: -3)
        ]
        #expect(TopAppAggregator.rows(metric: .cpu, samples: samples, applications: applications).isEmpty)
    }

    @Test func testTieUsesStableIdentityOrder() {
        let applications = [
            application(pid: 2, path: "/Applications/Z.app", name: "Z"),
            application(pid: 1, path: "/Applications/A.app", name: "A")
        ]
        let samples = [
            ProcessUsageSample(metadata: metadata(pid: 2), value: 5),
            ProcessUsageSample(metadata: metadata(pid: 1), value: 5)
        ]
        let rows = TopAppAggregator.rows(metric: .memory, samples: samples, applications: applications)
        #expect(rows.map(\.name) == ["A", "Z"])
    }
}
