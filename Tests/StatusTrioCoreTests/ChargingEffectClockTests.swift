import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct ChargingEffectClockTests {
    @Test func idleBatteryDoesNotStartATickLoop() {
        let time = ManualDateProvider()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)

        clock.update(
            battery: batteryStatus(61, charging: false),
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )

        #expect(clock.phase == nil)
        #expect(clock.isRunning == false)
        #expect(sleeper.callCount == 0)
    }

    @Test func chargingStartsOnePlugInBurstAndTicksEveryFiftyMilliseconds() async {
        let time = ManualDateProvider()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)

        clock.update(
            battery: batteryStatus(61, charging: true),
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )

        #expect(clock.phase?.kind == .burst)
        #expect(clock.phase?.step == 0)
        await sleeper.waitForCallCount(1)
        #expect(sleeper.durations.first == .milliseconds(50))

        time.advance(.milliseconds(50))
        sleeper.releaseAll()
        await sleeper.waitForCallCount(2)
        #expect(clock.phase?.kind == .burst)
        #expect(clock.phase?.step == 1)

        clock.stop()
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(2)
        #expect(sleeper.callCount == 2)
    }

    @Test func disablingTheSettingStopsImmediatelyAndDoesNotLeaveATick() async {
        await assertStopsImmediately(enabled: false, reduceMotion: false, displayAsleep: false)
    }

    @Test func unpluggingStopsImmediatelyAndDoesNotLeaveATick() async {
        await assertStopsImmediately(
            battery: batteryStatus(61, charging: false),
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )
    }

    @Test func reduceMotionStopsImmediatelyAndDoesNotLeaveATick() async {
        await assertStopsImmediately(enabled: true, reduceMotion: true, displayAsleep: false)
    }

    @Test func displaySleepStopsImmediatelyAndDoesNotLeaveATick() async {
        await assertStopsImmediately(enabled: true, reduceMotion: false, displayAsleep: true)
    }

    /// A hidden menu bar with no preview open has nothing to draw the phase, so
    /// the 20-Hz loop must not run at all — not merely render into the void.
    @Test func hiddenMenuBarWithoutAPreviewNeverStartsTheTickLoop() async {
        let time = ManualDateProvider()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let battery = batteryStatus(61, charging: true)

        clock.update(
            battery: battery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false,
            menuBarVisible: false
        )

        #expect(clock.hasAnimationSurface == false)
        #expect(clock.isRunning == false)
        #expect(clock.phase == nil)
        #expect(sleeper.callCount == 0)
    }

    /// Coming back from a hidden menu bar resumes where the battery is, and must
    /// not replay the plug-in burst for a charge that is already in progress.
    @Test func showingTheMenuBarAgainResumesSteadyWithoutARepriseBurst() async {
        let time = ManualDateProvider()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let battery = batteryStatus(61, charging: true)

        clock.update(
            battery: battery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false,
            menuBarVisible: false
        )
        #expect(sleeper.callCount == 0)

        clock.update(
            battery: battery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false,
            menuBarVisible: true
        )

        #expect(clock.isRunning)
        #expect(clock.phase?.kind == .steady)
        #expect(clock.phase?.step == 0)
        await sleeper.waitForCallCount(1)

        clock.stop()
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(1)
    }

    /// The settings preview draws the same live phase, so it keeps the clock
    /// alive while the menu bar is hidden and releases it on disappear.
    @Test func aVisiblePreviewKeepsTheClockAliveWhileTheMenuBarIsHidden() async {
        let time = ManualDateProvider()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let battery = batteryStatus(61, charging: true)
        let token = UUID()

        clock.update(
            battery: battery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false,
            menuBarVisible: false
        )
        #expect(clock.isRunning == false)

        clock.beginAnimationPreview(token)
        #expect(clock.hasAnimationSurface)
        #expect(clock.isRunning)
        #expect(clock.phase?.kind == .steady)
        await sleeper.waitForCallCount(1)

        clock.endAnimationPreview(token)
        #expect(clock.hasAnimationSurface == false)
        #expect(clock.isRunning == false)
        #expect(clock.phase == nil)

        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(1)
        #expect(sleeper.callCount == 1)
    }

    /// Appearing twice with one token, or disappearing without appearing, must
    /// not leave a claim behind that would keep the clock running forever.
    @Test func previewClaimsAreIdempotentAndDoNotLeak() {
        let time = ManualDateProvider()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let battery = batteryStatus(61, charging: true)
        let token = UUID()

        clock.update(
            battery: battery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false,
            menuBarVisible: false
        )

        clock.beginAnimationPreview(token)
        clock.beginAnimationPreview(token)
        clock.endAnimationPreview(token)
        clock.endAnimationPreview(token)
        clock.endAnimationPreview(UUID())

        #expect(clock.hasAnimationSurface == false)
        #expect(clock.isRunning == false)

        // Two different cards can hold claims at the same time.
        let firstToken = UUID()
        let secondToken = UUID()
        clock.beginAnimationPreview(firstToken)
        clock.beginAnimationPreview(secondToken)
        #expect(clock.isRunning)
        clock.endAnimationPreview(firstToken)
        #expect(clock.isRunning)
        clock.endAnimationPreview(secondToken)
        #expect(clock.isRunning == false)
    }

    @Test func wakingResumesWithAFreshSteadyPhase() async {
        let time = ManualDateProvider()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let battery = batteryStatus(61, charging: true)

        clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)
        await sleeper.waitForCallCount(1)
        clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: true)
        #expect(clock.phase == nil)
        #expect(clock.isRunning == false)

        clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)
        #expect(clock.phase?.kind == .steady)
        #expect(clock.phase?.step == 0)
        #expect(clock.isRunning)
        await sleeper.waitForCallCount(2)

        clock.stop()
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(2)
        #expect(sleeper.callCount == 2)
    }

    @Test func initialPlugInBurstTransitionsToSteadyExactlyOnce() async {
        let time = ManualDateProvider()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let battery = batteryStatus(61, charging: true)

        clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)
        for frame in 1...12 {
            await sleeper.waitForCallCount(frame)
            time.advance(.milliseconds(50))
            sleeper.releaseAll()
        }
        await sleeper.waitForCallCount(13)

        #expect(clock.phase?.kind == .steady)
        #expect(clock.phase?.step == 0)

        clock.stop()
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(13)
        #expect(sleeper.callCount == 13)
    }

    @Test func levelAdvanceDuringPlugInKeepsMenuBarBurst() async {
        let time = ManualDateProvider()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let initial = batteryStatus(61, charging: true)
        let increased = batteryStatus(62, charging: true)

        clock.update(battery: initial, enabled: true, reduceMotion: false, displayAsleep: false)
        await sleeper.waitForCallCount(1)
        time.setElapsed(0.25)
        clock.update(battery: initial, enabled: true, reduceMotion: false, displayAsleep: false)
        #expect(clock.phase?.kind == .burst)
        #expect(clock.phase?.step == 5)

        clock.update(battery: increased, enabled: true, reduceMotion: false, displayAsleep: false)

        #expect(clock.phase?.kind == .burst)
        #expect(clock.phase?.step == 5)

        time.setElapsed(0.3)
        clock.update(battery: increased, enabled: true, reduceMotion: false, displayAsleep: false)
        #expect(clock.phase?.kind == .burst)
        #expect(clock.phase?.step == 6)

        clock.stop()
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(1)
    }

    @Test func levelAdvanceBoostsTheNextHeartbeatWithoutResettingSteadyPosition() async {
        let time = ManualDateProvider()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let initial = batteryStatus(61, charging: true)
        let increased = batteryStatus(62, charging: true)

        clock.update(battery: initial, enabled: true, reduceMotion: false, displayAsleep: false)
        await sleeper.waitForCallCount(1)
        time.setElapsed(0.6)
        clock.update(battery: initial, enabled: true, reduceMotion: false, displayAsleep: false)
        time.setElapsed(2.1)
        clock.update(battery: initial, enabled: true, reduceMotion: false, displayAsleep: false)
        #expect(clock.phase?.kind == .steady)
        #expect(clock.phase?.step == 30)

        clock.update(battery: increased, enabled: true, reduceMotion: false, displayAsleep: false)
        #expect(clock.phase?.kind == .steady)
        #expect(clock.phase?.step == 30)
        #expect(clock.phase?.heartbeatMultiplier == 1.35)

        time.setElapsed(2.2)
        clock.update(battery: increased, enabled: true, reduceMotion: false, displayAsleep: false)
        #expect(clock.phase?.step == 32)
        #expect(clock.phase?.heartbeatMultiplier == 1.35)

        time.setElapsed(2.4)
        clock.update(battery: increased, enabled: true, reduceMotion: false, displayAsleep: false)
        #expect(clock.phase?.kind == .steady)
        #expect(clock.phase?.step == 0)
        #expect(clock.phase?.heartbeatMultiplier == 1)

        clock.stop()
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(1)
        #expect(sleeper.callCount == 1)
    }

    private func assertStopsImmediately(
        battery: BatteryStatus? = nil,
        enabled: Bool,
        reduceMotion: Bool,
        displayAsleep: Bool
    ) async {
        let time = ManualDateProvider()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)

        clock.update(
            battery: batteryStatus(61, charging: true),
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )
        await sleeper.waitForCallCount(1)

        clock.update(
            battery: battery ?? batteryStatus(61, charging: true),
            enabled: enabled,
            reduceMotion: reduceMotion,
            displayAsleep: displayAsleep
        )
        #expect(clock.phase == nil)
        #expect(clock.isRunning == false)

        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(1)
        #expect(sleeper.callCount == 1)
    }

    private func makeClock(
        time: ManualDateProvider,
        sleeper: ManualEventSleeper
    ) -> ChargingEffectClock {
        ChargingEffectClock(
            now: { time.now },
            sleep: { await sleeper.sleep($0) }
        )
    }

    private func batteryStatus(_ percentage: Int, charging: Bool) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: charging,
            isLowPowerMode: false,
            isConnectedToPower: charging
        )
    }
}

@MainActor
private final class ManualDateProvider {
    private let start = Date(timeIntervalSince1970: 1_000)
    private(set) var elapsed: TimeInterval = 0

    var now: Date {
        start.addingTimeInterval(elapsed)
    }

    func advance(_ duration: Duration) {
        elapsed += duration.timeInterval
    }

    func setElapsed(_ interval: TimeInterval) {
        elapsed = interval
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
