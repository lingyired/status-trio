import XCTest
@testable import StatusTrioCore

/// Runtime probes. They skip when the host lacks a capability, but still
/// exercise the real dynamic loading and libproc paths on supported Macs.
final class ApplicationEnergyRuntimeProbeTests: XCTestCase {
    func testReaderReturnsOwnProcessWithoutPrivileges() throws {
        let reader = ApplicationEnergyReader()
        let snapshot = reader.read(applications: [
            ProcessApplication(pid: getpid(), path: "/Probe.app", bundleID: nil, name: "Probe")
        ])
        XCTAssertGreaterThan(snapshot.readAt, 0)
        guard let own = snapshot.processes.first(where: { $0.pid == getpid() }) else {
            throw XCTSkip("libproc did not return the test process")
        }
        XCTAssertEqual(own.app.name, "Probe")
        XCTAssertTrue(snapshot.capabilities.contains(.cpuActivity))
        reader.reset()
    }

    func testReaderSamplingCost() {
        let reader = ApplicationEnergyReader()
        let applications = [
            ProcessApplication(pid: getpid(), path: "/Probe.app", bundleID: nil, name: "Probe")
        ]
        measure {
            _ = reader.read(applications: applications)
        }
        reader.reset()
    }

    func testGPUEnergyChannelIsMonotonicWhenAvailable() throws {
        guard GPUEnergyReader.isSupported else {
            throw XCTSkip("IOReport libIOReport symbols unavailable")
        }
        let reader = GPUEnergyReader()
        guard let first = reader.read() else {
            throw XCTSkip("GPU Energy channel unavailable on this host")
        }
        Thread.sleep(forTimeInterval: 0.2)
        if let second = reader.read() {
            XCTAssertGreaterThanOrEqual(second.joules, first.joules)
        }
        reader.reset()
    }
}
