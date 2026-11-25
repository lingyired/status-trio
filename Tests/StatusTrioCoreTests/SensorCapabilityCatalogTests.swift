import XCTest
@testable import StatusTrioCore

final class SensorCapabilityCatalogTests: XCTestCase {
    func testMachineIdentityParsesKnownAndUnknownChips() {
        func identity(_ name: String) -> MachineIdentity {
            MachineIdentity(chipName: name)
        }
        XCTAssertEqual(identity("Apple M1").chipFamily, .m1)
        XCTAssertEqual(identity("Apple M1 Pro").chipVariant, .pro)
        XCTAssertEqual(identity("Apple M2 Max").chipFamily, .m2)
        XCTAssertEqual(identity("Apple M2 Max").chipVariant, .max)
        XCTAssertEqual(identity("Apple M3").chipVariant, .base)
        XCTAssertEqual(identity("Apple M3 Ultra").chipVariant, .ultra)
        XCTAssertEqual(identity("Apple M4 Pro").chipFamily, .m4)
        XCTAssertEqual(identity("Apple M5").chipFamily, .m5)
        XCTAssertEqual(identity("Apple M5 Pro").chipVariant, .pro)
        XCTAssertEqual(identity("Apple M6 Max").chipFamily, .m6)
        XCTAssertEqual(identity("Apple A18 Pro").chipFamily, .a18Pro)
        XCTAssertEqual(identity("Intel(R) Core(TM) i9-9880H CPU @ 2.30GHz").chipFamily, .intel)
        // No silent inheritance from a neighbouring generation.
        XCTAssertEqual(identity("Apple M9").chipFamily, .unknown)
        XCTAssertEqual(identity("Apple A17 Pro").chipFamily, .unknown)
        XCTAssertEqual(identity("").chipFamily, .unknown)
    }

    func testM3BaseGPUUsesSixMeasuredTgPairs() {
        let identity = MachineIdentity(chipName: "Apple M3", modelIdentifier: "Mac15,12")
        let catalog = SensorCapabilityCatalog.catalog(for: identity)
        XCTAssertEqual(catalog.gpuPlan.groups.count, 6)
        XCTAssertEqual(catalog.gpuPlan.evidence, .communityMapped)
        let keys = Set(catalog.gpuPlan.keys)
        XCTAssertEqual(keys, Set(["Tg0O", "Tg0P", "Tg0C", "Tg0D", "Tg0W", "Tg0X",
                                  "Tg0a", "Tg0b", "Tg0i", "Tg0j", "Tg0u", "Tg0v"]))
        XCTAssertFalse(keys.contains("Tf14"))
        // Each pair is one group; the average cannot count 12 probes as 12 cores.
        XCTAssertTrue(catalog.gpuPlan.groups.allSatisfy { $0.definitions.count == 2 })
    }

    func testM3ProMaxDoesNotReuseM3BaseGPUPlan() {
        for name in ["Apple M3 Pro", "Apple M3 Max"] {
            let catalog = SensorCapabilityCatalog.catalog(for: MachineIdentity(chipName: name))
            XCTAssertTrue(catalog.gpuPlan.keys.contains("Tf14"))
            XCTAssertFalse(catalog.gpuPlan.keys.contains("Tg0O"))
            XCTAssertFalse(catalog.gpuPlan.fallbackGroups.isEmpty, "Tg* is only a fallback on Pro/Max")
        }
    }

    func testM5BaseAndProUseDisjointCPULayouts() {
        let base = SensorCapabilityCatalog.catalog(for: MachineIdentity(chipName: "Apple M5"))
        let pro = SensorCapabilityCatalog.catalog(for: MachineIdentity(chipName: "Apple M5 Pro"))
        XCTAssertEqual(base.cpuPlan.groups.count, 8, "4 Super + 4 Efficiency groups")
        XCTAssertTrue(base.cpuPlan.keys.contains("Te04"))
        XCTAssertFalse(base.cpuPlan.keys.contains("Tp0O"), "GPU-following probe is not a CPU core")
        XCTAssertEqual(pro.cpuPlan.groups.count, 8, "6 Super groups + 2 P clusters")
        XCTAssertTrue(pro.cpuPlan.keys.contains("Tm00"))
        XCTAssertFalse(pro.cpuPlan.keys.contains("Te04"), "M5 Pro/Max has no E-cores")
        XCTAssertNotEqual(Set(base.gpuPlan.keys), Set(pro.gpuPlan.keys))
    }

    func testM6ExcludesSoCDieProbesFromCPU() {
        let catalog = SensorCapabilityCatalog.catalog(for: MachineIdentity(chipName: "Apple M6"))
        XCTAssertEqual(catalog.cpuPlan.groups.count, 7, "2 Super + 4 Performance + 1 E-cluster")
        XCTAssertEqual(Set(catalog.cpuPlan.keys).intersection(["Te0c", "Te0h", "Te0i"]), [])
        XCTAssertEqual(catalog.gpuPlan.keys.count, 18)
    }

    func testA18ProHasItsOwnPlan() {
        let catalog = SensorCapabilityCatalog.catalog(for: MachineIdentity(chipName: "Apple A18 Pro"))
        XCTAssertEqual(catalog.identity.chipFamily, .a18Pro)
        XCTAssertFalse(catalog.cpuPlan.groups.isEmpty)
        XCTAssertEqual(catalog.gpuPlan.groups.count, 4)
        XCTAssertTrue(catalog.cpuPlan.keys.contains("Tp00"))
        XCTAssertFalse(catalog.cpuPlan.keys.contains("Tf04"))
    }

    func testUnknownChipHasNoTemperaturePlan() {
        let catalog = SensorCapabilityCatalog.catalog(for: MachineIdentity(chipName: "Apple M9"))
        XCTAssertTrue(catalog.cpuPlan.groups.isEmpty)
        XCTAssertTrue(catalog.gpuPlan.groups.isEmpty)
        XCTAssertTrue(catalog.batteryTemperatureKeys.isEmpty)
    }

    func testCacheSkipsKnownMissingKeysAndRetriesAfterBackoff() {
        let now = Date()
        let cache = SensorCapabilityCache(backoff: [30, 60])
        XCTAssertTrue(cache.shouldProbe("Tf14", at: now))
        cache.record("Tf14", value: nil, at: now)
        XCTAssertFalse(cache.shouldProbe("Tf14", at: now.addingTimeInterval(10)))
        XCTAssertTrue(cache.shouldProbe("Tf14", at: now.addingTimeInterval(31)))
        cache.record("Tf14", value: nil, at: now.addingTimeInterval(31))
        XCTAssertFalse(cache.shouldProbe("Tf14", at: now.addingTimeInterval(60)))
        XCTAssertTrue(cache.shouldProbe("Tf14", at: now.addingTimeInterval(92)))
    }

    func testCacheAlwaysProbesReadableKeysAndResets() {
        let now = Date()
        let cache = SensorCapabilityCache(backoff: [30])
        cache.record("Tp00", value: 50, at: now)
        XCTAssertTrue(cache.shouldProbe("Tp00", at: now.addingTimeInterval(1)))
        cache.record("Tf14", value: nil, at: now)
        XCTAssertFalse(cache.shouldProbe("Tf14", at: now.addingTimeInterval(1)))
        cache.reset()
        XCTAssertTrue(cache.shouldProbe("Tf14", at: now.addingTimeInterval(1)))
    }
}
