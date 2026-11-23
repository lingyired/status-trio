import Foundation
import Testing
@testable import StatusTrioCore

struct BluetoothBatteryReaderTests {
    @Test func parsesComponentAndAggregateBatteryLevels() throws {
        let json = try #require(
            """
            {
              "SPBluetoothDataType": [
                {
                  "device_connected": [
                    {
                      "AirPods Pro": {
                        "device_address": "AC:90:85:C2:9C:1F",
                        "device_batteryLevelMain": "95%",
                        "device_batteryLevelLeft": "85",
                        "device_batteryLevelRight": 80,
                        "device_batteryLevelCase": "70 %"
                      }
                    },
                    {
                      "Keyboard": {
                        "device_address": "D3-6D-6C-40-A3-2E",
                        "device_batteryLevel": "63%"
                      }
                    }
                  ],
                  "device_not_connected": [
                    {"Old AirPods": {
                      "device_address": "00:11:22:33:44:55",
                      "device_batteryLevelLeft": 12,
                      "device_batteryLevelRight": 15,
                      "device_batteryLevelCase": 20
                    }}
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        let levels = BluetoothBatteryReader.parse(json: json)
        let airPods = try #require(levels[BluetoothBatteryReader.normalizedAddress("ac9085c29c1f")])
        let keyboard = try #require(levels[BluetoothBatteryReader.normalizedAddress("D3:6D:6C:40:A3:2E")])

        #expect(airPods.main == 95)
        #expect(airPods.left == 85)
        #expect(airPods.right == 80)
        #expect(airPods.caseLevel == 70)
        #expect(airPods.summary == "95% · L 85% · R 80% · Case 70%")
        #expect(levels["001122334455"] == nil)
        #expect(keyboard.main == 63)
        #expect(keyboard.summary == "63%")
    }

    @Test func ignoresInvalidAndOutOfRangeLevels() throws {
        let json = try #require(
            """
            {
              "SPBluetoothDataType": [
                {
                  "device_connected": [
                    {
                      "Headphones": {
                        "device_address": "00:11:22:33:44:55",
                        "device_batteryLevelMain": "not available",
                        "device_batteryLevelLeft": 101,
                        "device_batteryLevelRight": -1,
                        "device_batteryLevelCase": "12.5"
                      }
                    }
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        #expect(BluetoothBatteryReader.parse(json: json).isEmpty)
    }

    /// Disconnected copies cannot replace a connected reading, and normalized
    /// duplicates across controller sections still yield one level.
    @Test func aDeviceListedTwiceKeepsTheConnectedLevel() throws {
        let json = try #require(
            """
            {
              "SPBluetoothDataType": [
                {
                  "device_connected": [
                    {"AirPods Pro": {
                      "device_address": "AC:90:85:C2:9C:1F",
                      "device_batteryLevelMain": "95%"
                    }}
                  ],
                  "device_not_connected": [
                    {"AirPods Pro": {
                      "device_address": "ac-90-85-c2-9c-1f",
                      "device_batteryLevelMain": "12%"
                    }}
                  ]
                },
                {"device_connected": [{"Duplicate AirPods": {
                  "device_address": "ac-90-85-c2-9c-1f",
                  "device_batteryLevelMain": 0
                }}]}
              ]
            }
            """.data(using: .utf8)
        )

        let levels = BluetoothBatteryReader.parse(json: json)

        #expect(levels.count == 1)
        #expect(
            levels[BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")]?.main == 95
        )
    }

    /// Only valid connected readings participate in address deduplication.
    @Test func anEntryWithoutALevelDoesNotShadowOneThatHasIt() throws {
        let json = try #require(
            """
            {
              "SPBluetoothDataType": [
                {
                  "device_connected": [
                    {"AirPods Pro": {
                      "device_address": "AC:90:85:C2:9C:1F",
                      "device_batteryLevelMain": "not available"
                    }},
                    {"Keyboard": {
                      "device_address": "00:11:22:33:44:55"
                    }},
                    {"Keyboard": {
                      "device_address": "00-11-22-33-44-55",
                      "device_batteryLevelMain": 100,
                      "device_batteryLevelLeft": 0
                    }}
                  ],
                  "device_not_connected": [
                    {"AirPods Pro": {
                      "device_address": "AC:90:85:C2:9C:1F",
                      "device_batteryLevelMain": "12%"
                    }}
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        let levels = BluetoothBatteryReader.parse(json: json)

        #expect(levels["001122334455"]?.main == 100)
        #expect(levels["001122334455"]?.left == 0)
        #expect(
            levels[BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")] == nil
        )
    }

    @Test func malformedOutputFailsClosed() {
        #expect(BluetoothBatteryReader.parse(json: Data("not json".utf8)).isEmpty)
    }

    private let sharedReport = """
    {
      "SPBluetoothDataType": [
        {
          "device_connected": [
            {
              "AirPods Pro": {
                "device_address": "AC:90:85:C2:9C:1F",
                "device_minorType": "Headphones",
                "device_batteryLevelMain": "95%"
              }
            }
          ],
          "device_not_connected": []
        }
      ]
    }
    """

    /// A report with no device and no battery level, used as the older entry a
    /// cache read may serve.
    private let emptyReport = """
    {"SPBluetoothDataType": [{"device_connected": [], "device_not_connected": []}]}
    """

    /// One refresh reads the paired devices and then the battery levels. Both
    /// parse the same JSON, so the second read must reuse the first report
    /// instead of running `/usr/sbin/system_profiler` again.
    @Test func batteryReadReusesTheDeviceReportWithoutSpawningAgain() async {
        let reportCache = BluetoothProfilerReportCache()
        let data = Data(sharedReport.utf8)
        let deviceWorker = SystemProfilerBluetoothPairedDeviceWorker(
            outputProvider: { data },
            reportCache: reportCache
        )
        let spawnCount = ProfilerSpawnCounter()
        let batteryWorker = SystemProfilerBluetoothBatteryWorker(
            outputProvider: {
                spawnCount.increment()
                return nil
            },
            reportCache: reportCache
        )

        let devices = DeviceResultBox()
        deviceWorker.read { devices.set($0) }
        await waitUntil { devices.value != nil }

        let levels = BatteryLevelResultBox()
        batteryWorker.read { levels.set($0) }
        await waitUntil { levels.hasAnswered }

        #expect(spawnCount.value == 0, "the battery read spawned a second profiler")
        #expect(levels.value?[BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")]?.main == 95)
    }

    @Test func cachedDisconnectedReportAnswersWithAnEmptySuccessfulRead() async {
        let reportCache = BluetoothProfilerReportCache()
        let data = Data("""
        {"SPBluetoothDataType": [{"device_not_connected": [{"AirPods": {
          "device_address": "AC:90:85:C2:9C:1F",
          "device_batteryLevelLeft": 12,
          "device_batteryLevelRight": 15,
          "device_batteryLevelCase": 20
        }}]}]}
        """.utf8)
        #expect(BluetoothBatteryReader.parse(json: data).isEmpty)
        reportCache.store(data)
        let spawnCount = ProfilerSpawnCounter()
        let worker = SystemProfilerBluetoothBatteryWorker(outputProvider: {
            spawnCount.increment()
            return nil
        }, reportCache: reportCache)
        let levels = BatteryLevelResultBox()
        worker.read { levels.set($0) }
        await waitUntil { levels.hasAnswered }
        #expect(levels.value == [:])
        #expect(spawnCount.value == 0)
    }

    /// A battery read that happens on its own has no fresh report to reuse, so
    /// it still asks the system for one and keeps that answer for the next read.
    @Test func batteryReadSpawnsWhenTheSharedReportIsStale() async {
        let reportCache = BluetoothProfilerReportCache()
        let stale = Data("""
        {"SPBluetoothDataType": [{"device_connected": [], "device_not_connected": []}]}
        """.utf8)
        reportCache.store(stale, at: Date().addingTimeInterval(-60))

        let spawnCount = ProfilerSpawnCounter()
        let data = Data(sharedReport.utf8)
        let batteryWorker = SystemProfilerBluetoothBatteryWorker(
            outputProvider: {
                spawnCount.increment()
                return data
            },
            reportCache: reportCache
        )

        let levels = BatteryLevelResultBox()
        batteryWorker.read { levels.set($0) }
        await waitUntil { levels.hasAnswered }

        #expect(spawnCount.value == 1)
        #expect(levels.value?[BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")]?.main == 95)
    }

    /// The report the shared path parses also carries the AirPods product ID
    /// that identifies the model for the row icon (`db6c7c2`) and, for a
    /// renamed device, decides whether the row claims a battery level at all
    /// (`463110d`). Both readers must derive exactly what they derived when each
    /// owned its own report, so the device and battery mapping is pinned against
    /// the direct-parse baseline.
    @Test func sharedReportKeepsTheSeparateReadsMapping() async {
        let report = """
        {
          "SPBluetoothDataType": [
            {
              "device_connected": [
                {
                  "小王的耳机": {
                    "device_address": "AC:90:85:C2:9C:1F",
                    "device_minorType": "Headphones",
                    "device_productID": "0x200F",
                    "device_vendorID": "0x004C",
                    "device_batteryLevelMain": "95%",
                    "device_batteryLevelLeft": "85",
                    "device_batteryLevelCase": "70"
                  }
                }
              ],
              "device_not_connected": [
                {
                  "MX Keys": {
                    "device_address": "D3:6D:6C:40:A3:2E",
                    "device_minorType": "Keyboard",
                    "device_batteryLevel": "63%"
                  }
                }
              ]
            }
          ]
        }
        """
        let data = Data(report.utf8)
        // The baseline: what each reader produced while it owned its own report.
        let expectedDevices = BluetoothPairedDeviceReader.parse(json: data)
        let expectedLevels = BluetoothBatteryReader.parse(json: data)

        let reportCache = BluetoothProfilerReportCache()
        let deviceWorker = SystemProfilerBluetoothPairedDeviceWorker(
            outputProvider: { data },
            reportCache: reportCache
        )
        let spawnCount = ProfilerSpawnCounter()
        let batteryWorker = SystemProfilerBluetoothBatteryWorker(
            outputProvider: {
                spawnCount.increment()
                return nil
            },
            reportCache: reportCache
        )

        let devices = DeviceResultBox()
        deviceWorker.read { devices.set($0) }
        await waitUntil { devices.value != nil }

        let levels = BatteryLevelResultBox()
        batteryWorker.read { levels.set($0) }
        await waitUntil { levels.hasAnswered }

        guard case let .success(sharedDevices) = devices.value else {
            Issue.record("expected a successful shared read, got \(String(describing: devices.value))")
            return
        }
        #expect(spawnCount.value == 0)
        #expect(sharedDevices == expectedDevices)
        #expect(levels.value == expectedLevels)

        // The signals the AirPods icon fix depends on: the product ID that names
        // the model, and the level that follows it.
        let address = BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")
        let airPods = sharedDevices.first { $0.id == "AC:90:85:C2:9C:1F" }
        #expect(airPods?.airPodsModel == .airPods)
        #expect(levels.value?[address]?.main == 95)
        #expect(levels.value?[address]?.left == 85)
        #expect(levels.value?[address]?.caseLevel == 70)
    }

    /// The freshness window runs from the last `store`, and a read that only
    /// reuses cached bytes must not store them back. Otherwise every
    /// battery-only read slides the window forward: a report produced 12 s ago
    /// is served because some read re-stamped it 3 s ago, which is the contract
    /// the cache claims and the one this test pins.
    ///
    /// The read is served from a report produced just inside the window, and
    /// the query afterwards is more than `defaultMaxAge` past *production*. If
    /// the read re-stamped the entry, that query would still find it fresh.
    @Test func cacheServedReadDoesNotExtendTheReportLifetime() async {
        let maxAge = BluetoothProfilerReportCache.defaultMaxAge
        let reportCache = BluetoothProfilerReportCache()
        // Produced `maxAge - 1` seconds ago: still fresh, so the read reuses it.
        let producedAt = Date().addingTimeInterval(-(maxAge - 1))
        reportCache.store(Data(sharedReport.utf8), at: producedAt)

        let spawnCount = ProfilerSpawnCounter()
        let batteryWorker = SystemProfilerBluetoothBatteryWorker(
            outputProvider: {
                spawnCount.increment()
                return nil
            },
            reportCache: reportCache
        )

        let levels = BatteryLevelResultBox()
        batteryWorker.read { levels.set($0) }
        await waitUntil { levels.hasAnswered }

        #expect(spawnCount.value == 0, "the read should reuse the fresh report")
        #expect(levels.value?[BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")]?.main == 95)
        #expect(
            reportCache.freshData(now: producedAt.addingTimeInterval(maxAge + 1)) == nil,
            "a cache-served read extended the report's life past the freshness window"
        )
    }

    /// The cache must never go backwards: a read that took bytes from the cache
    /// must not store them, because that store can land after a newer report the
    /// device worker stored and roll the cache back to the older bytes. The
    /// read-then-store pair is not atomic and the worker offers no seam between
    /// them, so the store call site is the only place this is observable
    /// without a test-only cache API; this pins it there.
    @Test func cacheServedReadDoesNotRollBackANewerStoredReport() async {
        let maxAge = BluetoothProfilerReportCache.defaultMaxAge
        let newer = Data(sharedReport.utf8)
        let reportCache = BluetoothProfilerReportCache()
        let producedAt = Date().addingTimeInterval(-(maxAge - 1))
        reportCache.store(Data(emptyReport.utf8), at: producedAt)

        let spawnCount = ProfilerSpawnCounter()
        let batteryWorker = SystemProfilerBluetoothBatteryWorker(
            outputProvider: {
                spawnCount.increment()
                return nil
            },
            reportCache: reportCache
        )

        // The read that took the older bytes. If it stored them, the entry's
        // window starts here instead of at `producedAt`, so the older bytes
        // stay servable past their production time.
        let olderRead = BatteryLevelResultBox()
        batteryWorker.read { olderRead.set($0) }
        await waitUntil { olderRead.hasAnswered }
        #expect(spawnCount.value == 0)
        #expect(
            reportCache.freshData(now: producedAt.addingTimeInterval(maxAge + 1)) == nil,
            "the read stored the older bytes it only read, making them servable again"
        )

        // The newer report the device worker stores while such a read is in
        // flight. The older bytes must not come back on top of it.
        reportCache.store(newer)
        let newerRead = BatteryLevelResultBox()
        batteryWorker.read { newerRead.set($0) }
        await waitUntil { newerRead.hasAnswered }

        #expect(spawnCount.value == 0)
        #expect(newerRead.value == BluetoothBatteryReader.parse(json: newer))
        #expect(reportCache.freshData() == newer)
    }

    /// A spawn that fails is not an empty report: the read answers with nothing
    /// so the page can tell "could not read" from "no device has a level".
    @Test func failedSpawnAnswersWithNothing() async {
        let batteryWorker = SystemProfilerBluetoothBatteryWorker(
            outputProvider: { nil },
            reportCache: BluetoothProfilerReportCache()
        )

        let levels = BatteryLevelResultBox()
        batteryWorker.read { levels.set($0) }
        await waitUntil { levels.hasAnswered }

        #expect(levels.value == nil)
    }

    /// The readers answer on their own serial queues.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for the profiler read")
    }
}

/// The workers answer on their own serial queues, so the tests collect results
/// and call counts behind a lock.
private final class ProfilerSpawnCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class DeviceResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: BluetoothWorkerResult?

    var value: BluetoothWorkerResult? { lock.withLock { stored } }
    func set(_ result: BluetoothWorkerResult) { lock.withLock { stored = result } }
}

private final class BatteryLevelResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: BluetoothBatteryLevel]?
    private var hasResult = false

    var value: [String: BluetoothBatteryLevel]? { lock.withLock { stored } }
    /// A read that answered with no levels still answered, so waiting on
    /// `value != nil` would never finish for a failed report.
    var hasAnswered: Bool { lock.withLock { hasResult } }

    func set(_ levels: [String: BluetoothBatteryLevel]?) {
        lock.withLock {
            stored = levels
            hasResult = true
        }
    }
}
