import XCTest
@testable import StatusTrioCore

/// Issue #263: the Dock is not the primary volume feedback surface, so a
/// continuous volume adjustment may repaint it at a bounded rate. These tests
/// pin the Dock-only volume coalescer: the newest value always lands, a burst
/// repaints at most once per interval, sub-threshold arc changes merge into the
/// trailing repaint, and cancelling drops the pending work.
@MainActor
final class DockVolumeRenderCoalescerTests: XCTestCase {
    private func arc(_ progress: Double, color: IconColorRole = .primary) -> FooterState {
        .arc(ArcState(progress: progress, color: color))
    }

    private func dots(
        _ activeCount: Int,
        color: IconColorRole = .primary,
        strokeScale: Double = 1.25
    ) -> FooterState {
        .dots(DotsState(count: 4, activeCount: activeCount, color: color, strokeScale: strokeScale))
    }

    // MARK: Classifier

    func testOnlyFooterValueChangesCountAsContinuousVolume() {
        let base = IconSceneState(footer: arc(0.4))

        XCTAssertTrue(
            IconSceneState(footer: arc(0.9)).isVolumeValueChange(from: base),
            "An arc progress change with the same colour and stroke is a volume value change."
        )
        XCTAssertFalse(
            base.isVolumeValueChange(from: base),
            "An unchanged scene is not a volume change."
        )
        XCTAssertFalse(
            IconSceneState(footer: arc(0.9, color: .bluetooth)).isVolumeValueChange(from: base),
            "A colour change comes from settings or the device, not a volume value."
        )
        XCTAssertFalse(
            IconSceneState(footer: dots(2)).isVolumeValueChange(from: base),
            "Switching the display style is a settings change, not a volume value change."
        )
        XCTAssertFalse(
            IconSceneState(
                center: .text(IconTextState(text: "5", color: .primary, scale: 1)),
                footer: arc(0.9)
            ).isVolumeValueChange(from: base),
            "A centre change must never be treated as a volume value change."
        )

        let dotsBase = IconSceneState(footer: dots(2))
        XCTAssertTrue(
            IconSceneState(footer: dots(3)).isVolumeValueChange(from: dotsBase),
            "A dot count change is a volume value change."
        )
        XCTAssertFalse(
            IconSceneState(footer: dots(3, strokeScale: 2)).isVolumeValueChange(from: dotsBase),
            "A stroke change is a settings change, not a volume value change."
        )
    }

    /// A Wi-Fi or battery footer changes far more slowly than a volume drag, and
    /// treating those updates as volume would rate-limit them behind an unrelated
    /// burst. Only the volume source may classify as a volume value change.
    func testNonVolumeSourcesAreNeverVolumeValueChanges() {
        let wifiBase = IconSceneState(footer: arc(0.2), bottomIndicatorSource: .wifi)
        XCTAssertFalse(
            IconSceneState(footer: arc(0.8), bottomIndicatorSource: .wifi)
                .isVolumeValueChange(from: wifiBase)
        )
        XCTAssertFalse(
            IconSceneState(footer: arc(0.8), bottomIndicatorSource: .battery)
                .isVolumeValueChange(from: IconSceneState(footer: arc(0.2), bottomIndicatorSource: .battery))
        )
        // Switching from Wi-Fi back to volume is a settings change, even though
        // the footer kind matches.
        XCTAssertFalse(
            IconSceneState(footer: arc(0.8), bottomIndicatorSource: .volume)
                .isVolumeValueChange(from: wifiBase)
        )
    }

    // MARK: Coalescer

    func testFirstVolumeChangeInAQuietPeriodRunsImmediately() {
        var renders: [String] = []
        let coalescer = DockVolumeRenderCoalescer(
            minimumInterval: 0.05,
            now: { Date() },
            sleep: { _ in }
        )

        coalescer.submit(footer: arc(0.4)) { renders.append("first") }

        XCTAssertEqual(
            renders,
            ["first"],
            "The first volume change of a quiet period must reach the Dock immediately."
        )
    }

    func testBurstKeepsOnlyTheNewestTrailingVolumeRender() async {
        let sleeper = ManualEventSleeper()
        let fixedDate = Date()
        var renders: [Double] = []
        let coalescer = makeCoalescer(sleeper: sleeper, now: { fixedDate })

        coalescer.submit(footer: arc(0.40)) { renders.append(0.40) }
        coalescer.submit(footer: arc(0.41)) { renders.append(0.41) }
        coalescer.submit(footer: arc(0.42)) { renders.append(0.42) }

        XCTAssertEqual(renders, [0.40], "A volume burst waits for the trailing render.")
        await sleeper.waitForCallCount(1)

        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(1)
        await waitUntil { renders.count == 2 }

        XCTAssertEqual(
            renders,
            [0.40, 0.42],
            "The trailing render must use the newest value, not an intermediate one."
        )
        XCTAssertEqual(sleeper.durations.count, 1)
        XCTAssertLessThanOrEqual(sleeper.durations[0], .seconds(0.05))
    }

    func testSubThresholdArcChangeMergesIntoTheTrailingRender() async {
        let sleeper = ManualEventSleeper()
        let fixedDate = Date()
        var renders: [Double] = []
        let coalescer = makeCoalescer(sleeper: sleeper, now: { fixedDate }, arcMergeThreshold: 0.01)

        coalescer.submit(footer: arc(0.400)) { renders.append(0.400) }
        XCTAssertEqual(renders, [0.400])

        coalescer.submit(footer: arc(0.401)) { renders.append(0.401) }

        XCTAssertEqual(
            renders,
            [0.400],
            "A sub-threshold arc change must not repaint the Dock on its own."
        )
        await sleeper.waitForCallCount(1)
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(1)
        await waitUntil { renders.count == 2 }
        XCTAssertEqual(
            renders.last,
            0.401,
            "The merged value must still land exactly on the trailing render."
        )
    }

    func testDotCountChangeRepaintsImmediatelyAfterTheInterval() async {
        let sleeper = ManualEventSleeper()
        var now = Date()
        var renders: [Int] = []
        let coalescer = makeCoalescer(sleeper: sleeper, now: { now })

        coalescer.submit(footer: dots(1)) { renders.append(1) }
        XCTAssertEqual(renders, [1])

        now = now.addingTimeInterval(0.2)
        coalescer.submit(footer: dots(2)) { renders.append(2) }

        XCTAssertEqual(
            renders,
            [1, 2],
            "A dot step is a visible change and must repaint once the interval has elapsed."
        )
    }

    func testCancelDropsThePendingVolumeRender() async {
        let sleeper = ManualEventSleeper()
        let fixedDate = Date()
        var renders: [String] = []
        let coalescer = makeCoalescer(sleeper: sleeper, now: { fixedDate })

        coalescer.submit(footer: arc(0.40)) { renders.append("first") }
        coalescer.submit(footer: arc(0.50)) { renders.append("pending") }
        await sleeper.waitForCallCount(1)

        coalescer.cancel()
        sleeper.releaseAll()

        XCTAssertEqual(renders, ["first"], "A cancelled coalescer must not run its trailing render.")
    }

    func testFlushPendingRunsTheNewestVolumeRender() async {
        let sleeper = ManualEventSleeper()
        let fixedDate = Date()
        var renders: [Double] = []
        let coalescer = makeCoalescer(sleeper: sleeper, now: { fixedDate })

        coalescer.submit(footer: arc(0.40)) { renders.append(0.40) }
        coalescer.submit(footer: arc(0.55)) { renders.append(0.55) }
        await sleeper.waitForCallCount(1)

        coalescer.flushPending()

        XCTAssertEqual(
            renders,
            [0.40, 0.55],
            "The deterministic drain boundary must run the newest pending value exactly once."
        )
    }

    // MARK: Helpers

    private func makeCoalescer(
        sleeper: ManualEventSleeper,
        now: @escaping () -> Date,
        arcMergeThreshold: Double = DockVolumeRenderCoalescer.defaultArcMergeThreshold
    ) -> DockVolumeRenderCoalescer {
        DockVolumeRenderCoalescer(
            minimumInterval: 0.05,
            arcMergeThreshold: arcMergeThreshold,
            now: now,
            sleep: { await sleeper.sleep($0) }
        )
    }

    private func waitUntil(_ condition: () -> Bool, attempts: Int = 200) async {
        for _ in 0..<attempts {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("The coalesced Dock volume redraw never ran.")
    }
}
