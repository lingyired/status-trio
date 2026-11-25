import Sparkle
import Testing
@testable import StatusTrioCore

@MainActor
struct UpdaterManagerFullScreenTests {
    @Test
    func defersOnlyScheduledChecksWhileFullScreenIsActive() {
        let manager = UpdaterManager.shared
        let originalProbe = manager.isFullScreenActive
        defer { manager.isFullScreenActive = originalProbe }

        manager.isFullScreenActive = { true }
        #expect(manager.shouldDeferUpdateCheck(.updatesInBackground))
        // A check the user explicitly asked for must never be postponed.
        #expect(!manager.shouldDeferUpdateCheck(.updates))

        manager.isFullScreenActive = { false }
        #expect(!manager.shouldDeferUpdateCheck(.updatesInBackground))
    }
}
