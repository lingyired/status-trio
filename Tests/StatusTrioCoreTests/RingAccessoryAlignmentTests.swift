import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

/// Issue #30 follow-up — the *top ring accessory* (plug / bolt / battery
/// percentage) must sit on the same artwork centre line as the battery ring and
/// the central glyph.
///
/// These are exact geometry tests, not screen screenshots: each accessory is
/// rendered in isolation (`regions: .ringAccessory`) so no ring arc or centre
/// glyph pixels can bias the measurement. Real-screen rasterisation is covered
/// separately by `scripts/run-menubar-accessory-alignment.py`.
///
/// Two centres are reported for every accessory:
///   * bbox centre      — midpoint of the ink's bounding box (what the layout
///                        code aligns to);
///   * alpha-weighted    — the area centre of mass (a proxy for the optical
///                        centre of an asymmetric shape such as the bolt).
/// The bolt is deliberately asymmetric, so its weighted centre is allowed a
/// slightly larger optical tolerance than its bbox centre; the plug and the
/// percentage text are held to the bbox contract.
@MainActor
final class RingAccessoryAlignmentTests: XCTestCase {
    private let size: CGFloat = 120
    private let scale: CGFloat = 8
    private let centre = StatusIconGeometry.artworkCenterX

    // MARK: - Accessory builders (mirror IconPresentationMapper gap content)

    private func plug() -> RingAccessoryState {
        .symbol(IconSymbolState(source: .primitive(.plug), color: .primary, scale: 1.8))
    }
    private func bolt() -> RingAccessoryState {
        .symbol(IconSymbolState(source: .primitive(.bolt), color: .primary, scale: 1.8))
    }
    private func percent(_ text: String) -> RingAccessoryState {
        .text(IconTextState(text: text, color: .primary, scale: 1.8))
    }

    private func scene(_ accessory: RingAccessoryState, gap: RingGapStyle) -> IconSceneState {
        IconSceneState(outerRing: OuterRingState(
            segments: [RingSegmentState(progress: 0, color: .powered)],
            gap: gap,
            accessory: accessory
        ))
    }

    private struct Measurement {
        let bboxCentre: CGFloat
        let weightedCentre: CGFloat
        let width: CGFloat
    }

    private func measure(_ accessory: RingAccessoryState, gap: RingGapStyle) throws -> Measurement {
        let image = try XCTUnwrap(StatusIconRenderer.render(
            scene: scene(accessory, gap: gap),
            environment: StatusIconRenderEnvironment(
                size: size,
                scale: scale,
                foreground: CGColor(gray: 1, alpha: 1),
                criticalColor: StatusIconRenderer.defaultCriticalColor
            ),
            regions: .ringAccessory
        ))
        let pixels = try PixelBuffer(image: image)
        let full = CGRect(x: 0, y: 0, width: size, height: size)
        let bounds = try XCTUnwrap(
            pixels.alphaBounds(inSVGRect: full, size: size, scale: scale, minimumAlpha: 24),
            "accessory drew no ink"
        )
        let weighted = try XCTUnwrap(pixels.alphaWeightedCentreX(
            inSVGRect: full, size: size, scale: scale))
        return Measurement(
            bboxCentre: (bounds.minX + bounds.maxX) / 2,
            weightedCentre: weighted,
            width: bounds.maxX - bounds.minX
        )
    }

    // MARK: - Tests

    func testPlugBoltAndPercentageSitOnTheArtworkCentreLine() throws {
        // bbox centre is the layout contract for every accessory. The bolt is an
        // asymmetric shape, so its alpha-weighted (optical) centre is allowed a
        // slightly wider tolerance — the task forbids forcing a bolt's pixel
        // centroid onto the ring if that distorts the intended design. Percentage
        // text is judged on its ink bbox only (its alpha mass is dominated by
        // glyph shape, not placement).
        struct Case { let name: String; let accessory: RingAccessoryState
                      let gap: RingGapStyle; let bboxTol: CGFloat
                      let weightedTol: CGFloat? }
        let cases: [Case] = [
            Case(name: "plug", accessory: plug(), gap: .indicator,
                 bboxTol: 0.15, weightedTol: 0.20),
            Case(name: "bolt", accessory: bolt(), gap: .indicator,
                 bboxTol: 0.15, weightedTol: 0.35),
            Case(name: "percent8", accessory: percent("8"), gap: .value,
                 bboxTol: 0.15, weightedTol: nil),
            Case(name: "percent50", accessory: percent("50"), gap: .value,
                 bboxTol: 0.15, weightedTol: nil),
            Case(name: "percent100", accessory: percent("100"), gap: .value,
                 bboxTol: 0.15, weightedTol: nil),
        ]
        for c in cases {
            let m = try measure(c.accessory, gap: c.gap)
            print("[RingAccessory] \(c.name): bbox=\(m.bboxCentre) " +
                  "weighted=\(m.weightedCentre) width=\(m.width) centre=\(centre)")
            XCTAssertEqual(m.bboxCentre, centre, accuracy: c.bboxTol,
                           "\(c.name) bbox centre off the artwork centre line")
            if let tol = c.weightedTol {
                XCTAssertEqual(m.weightedCentre, centre, accuracy: tol,
                               "\(c.name) optical (alpha-weighted) centre off centre")
            }
        }
    }

    /// Swapping the plug for the bolt must not shift the centre sideways — the
    /// two glyphs share one slot and must read as the same position.
    func testPlugAndBoltShareTheSameCentre() throws {
        let p = try measure(plug(), gap: .indicator)
        let b = try measure(bolt(), gap: .indicator)
        print("[RingAccessory] plug.bbox=\(p.bboxCentre) bolt.bbox=\(b.bboxCentre)")
        XCTAssertEqual(p.bboxCentre, b.bboxCentre, accuracy: 0.15,
                       "plug and bolt bbox centres must coincide in the shared slot")
    }

    /// Digit count changes the advance width; the visible ink must stay centred
    /// regardless of how many digits the percentage has.
    func testPercentageValuesShareOneInkCentre() throws {
        var centres: [String: CGFloat] = [:]
        for text in ["8", "50", "100"] {
            centres[text] = try measure(percent(text), gap: .value).bboxCentre
        }
        print("[RingAccessory] percent centres: \(centres)")
        let values = Array(centres.values)
        let minC = try XCTUnwrap(values.min())
        let maxC = try XCTUnwrap(values.max())
        XCTAssertLessThanOrEqual(maxC - minC, 0.15,
            "percentage ink centre moved across 1/2/3 digit values: \(centres)")
    }

    /// The ring's own geometric centre is the reference axis and must not move
    /// when an accessory appears: the battery centre is fixed.
    func testRingCentreIsIndependentOfAccessory() {
        XCTAssertEqual(StatusIconGeometry.artworkCenterX, 59.5, accuracy: 0.0001)
    }
}

private extension PixelBuffer {
    /// Alpha-weighted x centre of the ink inside `rect`, in scene units.
    func alphaWeightedCentreX(
        inSVGRect rect: CGRect,
        size: CGFloat,
        scale: CGFloat
    ) -> CGFloat? {
        let ppu = size * scale / StatusIconGeometry.canvas.width
        let minX = max(0, Int((rect.minX * ppu).rounded(.down)))
        let maxX = min(width, Int((rect.maxX * ppu).rounded(.up)))
        let minY = max(0, Int((rect.minY * ppu).rounded(.down)))
        let maxY = min(height, Int((rect.maxY * ppu).rounded(.up)))
        guard minX < maxX, minY < maxY else { return nil }
        var weighted = 0.0
        var total = 0.0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let a = Double(rgba(x: x, y: y).alpha)
                guard a > 0 else { continue }
                weighted += (Double(x) + 0.5) / Double(ppu) * a
                total += a
            }
        }
        guard total > 0 else { return nil }
        return CGFloat(weighted / total)
    }
}
