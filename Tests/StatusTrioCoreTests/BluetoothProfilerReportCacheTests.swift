import Foundation
import Testing
@testable import StatusTrioCore

struct BluetoothProfilerReportCacheTests {
    @Test func expiredReadRemovesTheStoredEntry() {
        let cache = BluetoothProfilerReportCache()
        let data = Data("report".utf8)
        let producedAt = Date(timeIntervalSince1970: 1_000)
        cache.store(data, at: producedAt)

        #expect(cache.freshData(maxAge: 30, now: producedAt.addingTimeInterval(30)) == nil)
        #expect(cache.storedEntryCount == 0)
    }

    @Test func callerMaxAgeControlsInvalidation() {
        let cache = BluetoothProfilerReportCache()
        let data = Data("report".utf8)
        let producedAt = Date(timeIntervalSince1970: 2_000)
        cache.store(data, at: producedAt)

        #expect(cache.freshData(maxAge: 60, now: producedAt.addingTimeInterval(30)) == data)
        #expect(cache.storedEntryCount == 1)
        #expect(
            cache.freshData(maxAge: 60, now: producedAt.addingTimeInterval(30)) == data,
            "custom maxAge keeps the entry beyond the default five-second window"
        )
        #expect(cache.freshData(maxAge: 10, now: producedAt.addingTimeInterval(30)) == nil)
        #expect(cache.storedEntryCount == 0)
    }

    @Test func returnedDataRemainsValidAfterCacheEntryIsRemoved() {
        let cache = BluetoothProfilerReportCache()
        let data = Data("report".utf8)
        let now = Date()
        cache.store(data, at: now)
        let returned = cache.freshData(maxAge: 5, now: now)!

        cache.reset()

        #expect(cache.storedEntryCount == 0)
        #expect(returned == data, "returned bytes have a caller-owned value lifetime")
    }

    @Test func resetRejectsAnInFlightStoreFromThePriorEpoch() {
        let cache = BluetoothProfilerReportCache()
        let stale = Data("pre-reset report".utf8)
        let fresh = Data("post-reset report".utf8)
        let now = Date()
        let epochCapturedBeforeFetch = cache.currentEpoch

        cache.reset()
        let epochCapturedAfterReset = cache.currentEpoch
        #expect(cache.store(fresh, at: now, ifCurrent: epochCapturedAfterReset))
        #expect(!cache.store(stale, at: now.addingTimeInterval(1), ifCurrent: epochCapturedBeforeFetch))
        #expect(cache.freshData(maxAge: 60, now: now.addingTimeInterval(2)) == fresh)
    }

}
