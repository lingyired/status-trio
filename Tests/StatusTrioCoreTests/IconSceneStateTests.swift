import Foundation
import XCTest
@testable import StatusTrioCore

final class IconSceneStateTests: XCTestCase {
    func testNonFiniteArcIsAnEmptyFill() {
        let invalid = ArcState(progress: .nan, color: .primary, strokeScale: 1)
        let empty = ArcState(progress: 0, color: .primary, strokeScale: 1)

        XCTAssertEqual(invalid, empty)
        XCTAssertEqual(Set([invalid, empty]).count, 1)
    }

    func testProgressIsFiniteAndClamped() {
        XCTAssertEqual(ArcState(progress: -.infinity, color: .primary, strokeScale: 1).progress, 0)
        XCTAssertEqual(ArcState(progress: 1.5, color: .primary, strokeScale: 1).progress, 1)
        XCTAssertEqual(RingSegmentState(progress: .nan, color: .primary).progress, 0)
        XCTAssertEqual(RingSegmentState(progress: -0.2, color: .primary).progress, 0)
        XCTAssertEqual(RingSegmentState(progress: 1.2, color: .primary).progress, 1)
    }

    func testDotCountsAreNormalized() {
        let tooManyActive = DotsState(count: 3, activeCount: 5, color: .primary, strokeScale: 1)
        let tooFewActive = DotsState(count: 3, activeCount: -1, color: .primary, strokeScale: 1)
        let negativeCount = DotsState(count: -2, activeCount: 1, color: .primary, strokeScale: 1)

        XCTAssertEqual(tooManyActive.activeCount, 3)
        XCTAssertEqual(tooFewActive.activeCount, 0)
        XCTAssertEqual(negativeCount.count, 0)
        XCTAssertEqual(negativeCount.activeCount, 0)
    }

    func testUnusedSceneAndRingAccessorySlotsDefaultToNil() {
        XCTAssertEqual(IconSceneState(), IconSceneState(outerRing: nil, center: nil, footer: nil))
        XCTAssertEqual(
            OuterRingState(segments: [], gap: .closed),
            OuterRingState(
                segments: [],
                gap: .closed,
                accessory: nil,
                effect: nil
            )
        )
    }

    func testIconSymbolSourceDoesNotCarryNonFiniteVariableValueIntoState() {
        let state = IconSymbolState(
            source: .symbol(name: "wifi", variableValue: .nan, fallback: nil),
            color: .primary,
            scale: 1
        )

        XCTAssertEqual(
            state,
            IconSymbolState(
                source: .symbol(name: "wifi", variableValue: nil, fallback: nil),
                color: .primary,
                scale: 1
            )
        )

        XCTAssertEqual(
            IconSymbolState(
                source: .symbol(name: "wifi", variableValue: -1, fallback: nil),
                color: .primary,
                scale: 1
            ).source,
            .symbol(name: "wifi", variableValue: 0, fallback: nil)
        )
        XCTAssertEqual(
            IconSymbolState(
                source: .symbol(name: "wifi", variableValue: 2, fallback: nil),
                color: .primary,
                scale: 1
            ).source,
            .symbol(name: "wifi", variableValue: 1, fallback: nil)
        )
    }

    func testScalesUseContextNeutralFallbacksAndKeepValidatedValues() {
        XCTAssertEqual(IconSymbolState(
            source: .primitive(.bolt), color: .primary, scale: .nan
        ).scale, 1)
        XCTAssertEqual(IconSymbolState(
            source: .primitive(.bolt), color: .primary, scale: 0
        ).scale, 1)
        XCTAssertEqual(IconSymbolState(
            source: .primitive(.bolt), color: .primary, scale: 1.8
        ).scale, 1.8)
        XCTAssertEqual(IconTextState(text: "50", color: .primary, scale: -.infinity).scale, 1)
        XCTAssertEqual(IconTextState(text: "50", color: .primary, scale: 1.62).scale, 1.62)

        XCTAssertEqual(OuterRingState(
            segments: [], gap: .closed, accessory: nil, effect: nil, strokeScale: .nan
        ).strokeScale, 1.25)
        XCTAssertEqual(OuterRingState(
            segments: [], gap: .closed, accessory: nil, effect: nil, strokeScale: 0.1
        ).strokeScale, 0.5)
        XCTAssertEqual(OuterRingState(
            segments: [], gap: .closed, accessory: nil, effect: nil, strokeScale: 3
        ).strokeScale, 2.5)
    }

    func testVisualPropertiesParticipateInStateEqualityAndHashing() {
        let symbol = IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 0.5, fallback: "wifi"),
            color: .primary,
            scale: 1
        )
        let sameSymbol = IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 0.5, fallback: "wifi"),
            color: .primary,
            scale: 1
        )
        XCTAssertEqual(symbol, sameSymbol)
        XCTAssertEqual(Set([symbol, sameSymbol]).count, 1)
        XCTAssertNotEqual(symbol, IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 0.5, fallback: "wifi"),
            color: .inactive,
            scale: 1
        ))
        XCTAssertNotEqual(symbol, IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 0.5, fallback: "wifi"),
            color: .primary,
            scale: 1.1
        ))
        XCTAssertNotEqual(symbol, IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 0.6, fallback: "wifi"),
            color: .primary,
            scale: 1
        ))
        XCTAssertNotEqual(symbol, IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 0.5, fallback: "wifi.slash"),
            color: .primary,
            scale: 1
        ))
        XCTAssertNotEqual(symbol, IconSymbolState(
            source: .primitive(.wiredPort), color: .primary, scale: 1
        ))

        let ring = OuterRingState(
            segments: [RingSegmentState(progress: 0.5, color: .primary)],
            gap: .closed,
            accessory: nil,
            effect: nil,
            strokeScale: 1
        )
        XCTAssertNotEqual(ring, OuterRingState(
            segments: [RingSegmentState(progress: 0.5, color: .critical)],
            gap: .closed,
            accessory: nil,
            effect: nil,
            strokeScale: 1
        ))
        XCTAssertNotEqual(ring, OuterRingState(
            segments: [RingSegmentState(progress: 0.5, color: .primary)],
            gap: .closed,
            accessory: .text(IconTextState(text: "50", color: .primary, scale: 1)),
            effect: nil,
            strokeScale: 1
        ))
        XCTAssertNotEqual(ring, OuterRingState(
            segments: [RingSegmentState(progress: 0.5, color: .primary)],
            gap: .indicator,
            accessory: nil,
            effect: nil,
            strokeScale: 1
        ))
        XCTAssertNotEqual(ring, OuterRingState(
            segments: [RingSegmentState(progress: 0.5, color: .primary)],
            gap: .closed,
            accessory: .symbol(symbol),
            effect: nil,
            strokeScale: 1
        ))
        XCTAssertNotEqual(ring, OuterRingState(
            segments: [RingSegmentState(progress: 0.5, color: .primary)],
            gap: .closed,
            accessory: nil,
            effect: RingEffectState(pulsesAccessory: true, tintsAccessory: false),
            strokeScale: 1
        ))
        XCTAssertNotEqual(ring, OuterRingState(
            segments: [RingSegmentState(progress: 0.5, color: .primary)],
            gap: .closed,
            accessory: nil,
            effect: RingEffectState(pulsesAccessory: false, tintsAccessory: true),
            strokeScale: 1
        ))
        XCTAssertNotEqual(ring, OuterRingState(
            segments: [RingSegmentState(progress: 0.5, color: .primary)],
            gap: .closed,
            accessory: nil,
            effect: nil,
            strokeScale: 1.1
        ))
        XCTAssertNotEqual(ring, OuterRingState(
            segments: [RingSegmentState(progress: 0.6, color: .primary)],
            gap: .closed,
            accessory: nil,
            effect: nil,
            strokeScale: 1
        ))

        XCTAssertNotEqual(
            CenterState.symbol(symbol),
            .text(IconTextState(text: "50", color: .primary, scale: 1))
        )
        XCTAssertNotEqual(
            IconTextState(text: "50", color: .primary, scale: 1),
            IconTextState(text: "51", color: .primary, scale: 1)
        )
        XCTAssertNotEqual(
            IconTextState(text: "50", color: .primary, scale: 1),
            IconTextState(text: "50", color: .critical, scale: 1)
        )
        XCTAssertNotEqual(
            IconTextState(text: "50", color: .primary, scale: 1),
            IconTextState(text: "50", color: .primary, scale: 1.1)
        )

        XCTAssertNotEqual(
            FooterState.dots(DotsState(count: 4, activeCount: 2, color: .primary, strokeScale: 1)),
            .arc(ArcState(progress: 0.5, color: .primary, strokeScale: 1))
        )
        XCTAssertNotEqual(
            DotsState(count: 4, activeCount: 2, color: .primary, strokeScale: 1),
            DotsState(count: 4, activeCount: 3, color: .primary, strokeScale: 1)
        )
        XCTAssertNotEqual(
            DotsState(count: 4, activeCount: 2, color: .primary, strokeScale: 1),
            DotsState(count: 5, activeCount: 2, color: .primary, strokeScale: 1)
        )
        XCTAssertNotEqual(
            DotsState(count: 4, activeCount: 2, color: .primary, strokeScale: 1),
            DotsState(count: 4, activeCount: 2, color: .critical, strokeScale: 1)
        )
        XCTAssertNotEqual(
            DotsState(count: 4, activeCount: 2, color: .primary, strokeScale: 1),
            DotsState(count: 4, activeCount: 2, color: .primary, strokeScale: 1.1)
        )
        XCTAssertNotEqual(
            ArcState(progress: 0.5, color: .primary, strokeScale: 1),
            ArcState(progress: 0.5, color: .critical, strokeScale: 1)
        )
        XCTAssertNotEqual(
            ArcState(progress: 0.5, color: .primary, strokeScale: 1),
            ArcState(progress: 0.5, color: .primary, strokeScale: 1.1)
        )
        XCTAssertNotEqual(
            IconSceneState(outerRing: ring, center: .symbol(symbol), footer: nil),
            IconSceneState(outerRing: nil, center: .symbol(symbol), footer: nil)
        )
        XCTAssertNotEqual(
            IconSceneState(outerRing: ring, center: .symbol(symbol), footer: nil),
            IconSceneState(outerRing: ring, center: nil, footer: nil)
        )
        XCTAssertNotEqual(
            IconSceneState(outerRing: ring, center: .symbol(symbol), footer: nil),
            IconSceneState(
                outerRing: ring,
                center: .symbol(symbol),
                footer: .dots(DotsState(count: 4, activeCount: 2, color: .primary))
            )
        )
    }
}
