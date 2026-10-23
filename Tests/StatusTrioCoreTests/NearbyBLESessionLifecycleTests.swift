import Foundation
import Testing
@testable import StatusTrioCore

struct NearbyBLESessionLifecycleTests {
    @Test func sessionTokenMustBePresentAndMatchTheCurrentGrant() {
        let id = UUID()
        var authorization = NearbyBLEReadAuthorization()
        _ = authorization.update([id])
        let token = authorization.token(for: id)

        #expect(!authorization.permits(id, token: nil))
        #expect(token.map { authorization.permits(id, token: $0) } == true)
        #expect(!NearbyBLEReadAuthorization().permits(id, token: token))
    }

    @Test func revokedUUIDCannotStartANewSessionUntilCancellationDrains() {
        var lifecycle = NearbyBLESessionCancellationGate()
        let id = UUID()
        let oldSession = UUID()
        let newSession = UUID()

        let beganOld = lifecycle.begin(id, session: oldSession)
        #expect(beganOld)
        let retiredOld = lifecycle.retire(id, session: oldSession)
        #expect(retiredOld)
        #expect(!lifecycle.isCurrent(id, session: oldSession))
        let beganDuringCancellation = lifecycle.begin(id, session: newSession)
        #expect(!beganDuringCancellation)

        let drainedOld = lifecycle.finishCancellation(id, session: oldSession)
        #expect(drainedOld)
        let beganNew = lifecycle.begin(id, session: newSession)
        #expect(beganNew)
        #expect(!lifecycle.isCurrent(id, session: oldSession))
        #expect(lifecycle.isCurrent(id, session: newSession))
        let duplicateOldDisconnect = lifecycle.finishCancellation(id, session: oldSession)
        #expect(!duplicateOldDisconnect)
        #expect(lifecycle.isCurrent(id, session: newSession), "a late old disconnect cannot retire the new session")
    }

    @Test func scannerStopRetiresAuthorizationTokenBeforeRestart() {
        let id = UUID()
        var authorization = NearbyBLEReadAuthorization()
        _ = authorization.update([id])
        let oldToken = authorization.token(for: id)

        _ = authorization.update([])
        _ = authorization.update([id])
        let newToken = authorization.token(for: id)

        #expect(oldToken != nil)
        #expect(newToken != nil)
        #expect(oldToken != newToken)
        #expect(oldToken.map { !authorization.accepts(id, token: $0) } == true)
        #expect(newToken.map { authorization.accepts(id, token: $0) } == true)
    }

    @MainActor
    @Test func stoppedScannerRetiresAllCurrentSessionChecks() {
        let scanner = CoreBluetoothLEBatteryScanner()
        scanner.stop()

        #expect(scanner.sessionAuthorizationCheckCount == 0)
        #expect(scanner.initialReadGrantCount == 0)
        #expect(scanner.readGrantCount == 0)
    }

}
