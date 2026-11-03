import AppKit
import SwiftUI

/// Shared geometry between the AppKit drawing and the SwiftUI inline label so
/// the painted track/thumb and the label position always agree.
enum PanelLevelSliderMetrics {
    /// Overall control height on screen.
    static let controlHeight: CGFloat = 30
    /// Visible capsule height.
    static let barHeight: CGFloat = 14
    /// White thumb circle diameter.
    static let thumbDiameter: CGFloat = 20
    static var thumbRadius: CGFloat { thumbDiameter / 2 }
    /// The thumb centre may travel between the capsule's leading/trailing insets.
    static var horizontalInset: CGFloat { thumbRadius }
    static var barCornerRadius: CGFloat { barHeight / 2 }

    /// Inline label inset from the capsule's leading/trailing edge.
    static let labelLeadingInset: CGFloat = 12
    /// Gap kept between the thumb edge and the inline label.
    static let labelGap: CGFloat = 8

    /// Thumb centre X for a value in 0...1 inside a given width.
    static func thumbCenterX(for value: Double, width: CGFloat) -> CGFloat {
        horizontalInset + CGFloat(value) * max(0, width - horizontalInset * 2)
    }
}

/// Pure layout for the optional inline label: which side of the thumb it parks
/// on (with hysteresis) and where it is drawn. Kept free of SwiftUI/AppKit so
/// the avoidance boundary can be unit-tested at 0/10/50/90/100%.
enum PanelLevelSliderLabelLayout {
    enum Side: Equatable {
        case leading
        case trailing
    }

    /// Hysteresis is expressed by "keep the current side while it still fits",
    /// so the switch threshold differs depending on travel direction.
    static let minimumVisibleWidth: CGFloat = 8

    /// Resolved placement of the label inside the capsule.
    struct Frame: Equatable {
        let side: Side
        let originX: CGFloat
        let width: CGFloat
        /// Labels narrower than this are hidden rather than drawn as a sliver.
        var isVisible: Bool { width > minimumVisibleWidth }
    }

    /// Decides which side of the thumb holds the label.
    ///
    /// Preference order: keep the current side if the full text still fits
    /// there; otherwise move to the other side if it fits; otherwise stay on
    /// the side with more room and truncate. This never overlaps the thumb and
    /// does not oscillate because each direction has its own "still fits" test.
    static func side(
        thumbCenterX: CGFloat,
        controlWidth: CGFloat,
        textWidth: CGFloat,
        currentlyTrailing: Bool
    ) -> Side {
        let leadingSpace = leadingAvailableSpace(
            thumbCenterX: thumbCenterX
        )
        let trailingSpace = trailingAvailableSpace(
            thumbCenterX: thumbCenterX,
            controlWidth: controlWidth
        )
        let fitsLeading = leadingSpace >= textWidth
        let fitsTrailing = trailingSpace >= textWidth

        if currentlyTrailing {
            if fitsTrailing { return .trailing }
            if fitsLeading { return .leading }
        } else {
            if fitsLeading { return .leading }
            if fitsTrailing { return .trailing }
        }
        // Neither side can hold the full text: truncate on the roomier side.
        return leadingSpace >= trailingSpace ? .leading : .trailing
    }

    static func leadingAvailableSpace(thumbCenterX: CGFloat) -> CGFloat {
        (thumbCenterX - PanelLevelSliderMetrics.thumbRadius
            - PanelLevelSliderMetrics.labelGap)
            - PanelLevelSliderMetrics.labelLeadingInset
    }

    static func trailingAvailableSpace(
        thumbCenterX: CGFloat,
        controlWidth: CGFloat
    ) -> CGFloat {
        (controlWidth - PanelLevelSliderMetrics.labelLeadingInset)
            - (thumbCenterX + PanelLevelSliderMetrics.thumbRadius
                + PanelLevelSliderMetrics.labelGap)
    }

    /// Resolves where the label can be drawn without being covered by the
    /// accent fill / thumb.
    static func frame(
        side: Side,
        thumbCenterX: CGFloat,
        controlWidth: CGFloat,
        textWidth: CGFloat
    ) -> Frame {
        let inset = PanelLevelSliderMetrics.labelLeadingInset
        let gap = PanelLevelSliderMetrics.labelGap
        let radius = PanelLevelSliderMetrics.thumbRadius

        let start: CGFloat
        let available: CGFloat
        switch side {
        case .leading:
            start = inset
            available = (thumbCenterX - radius - gap) - inset
        case .trailing:
            start = thumbCenterX + radius + gap
            available = (controlWidth - inset) - start
        }

        let width = max(0, min(textWidth, available))
        return Frame(side: side, originX: start, width: width)
    }

    /// Label ink colour: white over the accent fill (leading side), primary over
    /// the unfilled track (trailing side).
    static func usesLightText(side: Side) -> Bool {
        side == .leading
    }

    /// Measured width of the label text using the component's font.
    static func textWidth(_ text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium)
        ]
        return (text as NSString).size(withAttributes: attrs).width
    }
}

/// SwiftUI wrapper exposing the reusable panel level slider.
///
/// The component only owns appearance and basic interaction: produced values
/// are written straight into `value` and editing boundaries are surfaced via
/// `onEditingChanged`. It contains no volume/brightness business logic.
///
/// Vision (macOS inline capture): a 30pt rounded capsule, fully-rounded ends,
/// accent-filled progress, white thumb, and an optional single-line label that
/// lives inside the bar and dodges the thumb while never blocking input.
struct PanelLevelSlider: View {
    @Binding var value: Double
    var label: String? = nil
    var isEnabled: Bool = true
    var tint: Color = .accentColor
    var accessibilityLabel: String? = nil
    var accessibilityValue: String? = nil
    var onEditingChanged: (Bool) -> Void = { _ in }

    /// Hysteresis: once the label jumps to the thumb's trailing side it stays
    /// there until the thumb travels comfortably past again, so it never
    /// oscillates around a threshold.
    @State private var isLabelOnRight = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let centerX = PanelLevelSliderMetrics.thumbCenterX(
                for: Double(min(1, max(0, value))),
                width: width
            )
            ZStack(alignment: .leading) {
                Representable(
                    isEnabled: isEnabled,
                    tint: tint,
                    currentValue: value,
                    accessibilityLabel: accessibilityLabel,
                    accessibilityValue: accessibilityValue,
                    onValueChanged: { newValue in
                        value = newValue
                    },
                    onEditingChanged: onEditingChanged
                )

                if let label {
                    inlineLabel(
                        label,
                        side: isLabelOnRight ? .trailing : .leading,
                        thumbCenterX: centerX,
                        width: width
                    )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onAppear {
                applyLabelSide(value: value, width: width)
            }
            .onChange(of: value) { newValue in
                // Recompute from the *new* value: the closure captured the old
                // value, which would otherwise park the label at the old thumb
                // position (e.g. permanently at 0%).
                applyLabelSide(value: newValue, width: width)
            }
            .onChange(of: width) { newWidth in
                applyLabelSide(value: value, width: newWidth)
            }
        }
        .frame(height: PanelLevelSliderMetrics.controlHeight)
        // Accessibility lives on the native NSSlider so VoiceOver sees one
        // adjustable control with the same label/value the old Slider exposed.
    }

    // MARK: Inline label with thumb avoidance.

    private func measureWidth(_ text: String) -> CGFloat {
        PanelLevelSliderLabelLayout.textWidth(text)
    }

    /// Updates the parked side using hysteresis so the label does not flip back
    /// and forth exactly at the threshold. Called from view lifecycle hooks,
    /// never during `body` evaluation.
    private func applyLabelSide(value: Double, width: CGFloat) {
        guard let label else { return }
        let centerX = PanelLevelSliderMetrics.thumbCenterX(
            for: Double(min(1, max(0, value))),
            width: width
        )
        let side = PanelLevelSliderLabelLayout.side(
            thumbCenterX: centerX,
            controlWidth: width,
            textWidth: measureWidth(label),
            currentlyTrailing: isLabelOnRight
        )
        isLabelOnRight = (side == .trailing)
    }

    /// Pure presentation: places the single-line label where the fill/thumb
    /// cannot cover it, with truncation. Never touches interaction.
    @ViewBuilder
    private func inlineLabel(
        _ text: String,
        side: PanelLevelSliderLabelLayout.Side,
        thumbCenterX: CGFloat,
        width: CGFloat
    ) -> some View {
        let frame = PanelLevelSliderLabelLayout.frame(
            side: side,
            thumbCenterX: thumbCenterX,
            controlWidth: width,
            textWidth: measureWidth(text)
        )
        if frame.isVisible {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(labelForeground(side: frame.side))
                .frame(width: frame.width, alignment: .leading)
                .help(text)
                .offset(x: frame.originX, y: 0)
        }
    }

    private func labelForeground(side: PanelLevelSliderLabelLayout.Side) -> Color {
        guard isEnabled else { return .primary.opacity(0.6) }
        return PanelLevelSliderLabelLayout.usesLightText(side: side)
            ? Color.white.opacity(0.96)
            : Color.primary.opacity(0.92)
    }
}

private extension PanelLevelSlider {
    struct Representable: NSViewRepresentable {
        let isEnabled: Bool
        let tint: Color
        let currentValue: Double
        let accessibilityLabel: String?
        let accessibilityValue: String?
        let onValueChanged: (Double) -> Void
        let onEditingChanged: (Bool) -> Void

        func makeNSView(context: Context) -> PanelLevelSliderView {
            let slider = PanelLevelSliderView()
            slider.onValueChanged = onValueChanged
            slider.onEditingChanged = onEditingChanged
            slider.isEnabled = isEnabled
            slider.doubleValue = clamped(currentValue)
            applyAccessibility(to: slider)
            return slider
        }

        func updateNSView(_ nsView: PanelLevelSliderView, context: Context) {
            nsView.isEnabled = isEnabled
            nsView.fillColor = NSColor(tint)
            nsView.onValueChanged = onValueChanged
            nsView.onEditingChanged = onEditingChanged
            applyAccessibility(to: nsView)
            // Mirror external draft changes into the native control. During a
            // drag the produced value has already been written back, so this is
            // a no-op; a late system echo that did not originate from a drag is
            // applied normally (the panel-level state owns echo suppression).
            let target = clamped(currentValue)
            if abs(nsView.doubleValue - target) > 0.0001 {
                nsView.doubleValue = target
                nsView.needsDisplay = true
            }
        }

        private func applyAccessibility(to slider: PanelLevelSliderView) {
            slider.setAccessibilityLabel(accessibilityLabel)
            slider.setAccessibilityValue(accessibilityValue)
        }

        private func clamped(_ value: Double) -> Double {
            min(1, max(0, value))
        }
    }
}

/// AppKit slider that owns all drawing. Native `NSSlider` interaction (track
/// click jumps to the value, drag, keyboard arrows, VoiceOver) is preserved by
/// keeping the `NSSlider`/`NSSliderCell` machinery; only pixels are replaced.
final class PanelLevelSliderView: NSSlider {
    var onValueChanged: ((Double) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    var fillColor: NSColor = .controlAccentColor

    /// Marks tracking session boundaries so `mouseDown`/`mouseUp` around a
    /// super call always pairs, including for keyboard navigation.
    private var isGestureActive = false

    init() {
        super.init(frame: .zero)
        cell = PanelLevelSliderCell()
        minValue = 0
        maxValue = 1
        isContinuous = true
        isVertical = false
        sliderType = .linear
        target = self
        action = #selector(valueDidChange(_:))
        isEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    /// NSSlider reports a small intrinsic height (16pt). The panel capsule is
    /// taller, so report the design height; the SwiftUI frame then fills it and
    /// the ready-drawn capsule is vertically centred with the row's glyphs.
    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: PanelLevelSliderMetrics.controlHeight
        )
    }

    // MARK: Geometry shared with the cell.

    var clampedDoubleValue: Double {
        min(1, max(0, doubleValue))
    }

    func barRect(in bounds: NSRect) -> NSRect {
        let inset = PanelLevelSliderMetrics.horizontalInset
        let y = (bounds.height - PanelLevelSliderMetrics.barHeight) / 2
        return NSRect(
            x: inset,
            y: y,
            width: max(0, bounds.width - inset * 2),
            height: PanelLevelSliderMetrics.barHeight
        )
    }

    func knobCenter(in bounds: NSRect) -> NSPoint {
        let x = PanelLevelSliderMetrics.thumbCenterX(
            for: clampedDoubleValue,
            width: bounds.width
        )
        return NSPoint(x: x, y: bounds.midY)
    }

    // MARK: Drawing.

    @objc func valueDidChange(_ sender: Any?) {
        onValueChanged?(clampedDoubleValue)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawBarAndFill()
        drawKnob()
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private var effectiveFillColor: NSColor {
        isEnabled ? fillColor : NSColor.gray
    }

    private func drawBarAndFill() {
        let barRect = barRect(in: bounds)

        let trackColor = isDarkAppearance
            ? NSColor(white: 1.0, alpha: 0.14)
            : NSColor(white: 0.0, alpha: 0.10)
        let trackPath = NSBezierPath(
            roundedRect: barRect,
            xRadius: PanelLevelSliderMetrics.barCornerRadius,
            yRadius: PanelLevelSliderMetrics.barCornerRadius
        )
        trackColor.setFill()
        trackPath.fill()

        guard isEnabled, clampedDoubleValue > 0.001 else { return }
        let centerX = knobCenter(in: bounds).x
        let fillWidth = max(0, centerX - barRect.minX)
        guard fillWidth > 0.5 else { return }
        let fillRect = NSRect(
            x: barRect.minX,
            y: barRect.minY,
            width: min(fillWidth, barRect.maxX - barRect.minX),
            height: barRect.height
        )
        let fillPath = NSBezierPath(
            roundedRect: fillRect,
            xRadius: PanelLevelSliderMetrics.barCornerRadius,
            yRadius: PanelLevelSliderMetrics.barCornerRadius
        )
        effectiveFillColor.setFill()
        fillPath.fill()
    }

    private func drawKnob() {
        let center = knobCenter(in: bounds)
        let radius = PanelLevelSliderMetrics.thumbRadius
        let knobRect = NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = .zero
        shadow.set()

        let knob = NSBezierPath(ovalIn: knobRect)
        let knobColor: NSColor = isEnabled
            ? (isDarkAppearance ? NSColor.white : NSColor(calibratedWhite: 0.99, alpha: 1))
            : NSColor(white: isDarkAppearance ? 0.55 : 0.8, alpha: 1)
        knobColor.setFill()
        knob.fill()
    }

    // MARK: Interaction – report editing boundaries.

    override func mouseDown(with event: NSEvent) {
        guard !isGestureActive else { return }
        isGestureActive = true
        onEditingChanged?(true)
        super.mouseDown(with: event)
        onEditingChanged?(false)
        isGestureActive = false
    }

    /// Keys that move the native slider value. Only these open an editing
    /// session; Tab/Escape must not flush an adjustment that never happened.
    private static let adjustmentKeyCodes: Set<UInt16> = [
        123, // left arrow
        124, // right arrow
        125, // down arrow
        126, // up arrow
        115, // home
        119, // end
        116, // page up
        121, // page down
    ]

    override func keyDown(with event: NSEvent) {
        guard Self.adjustmentKeyCodes.contains(event.keyCode) else {
            super.keyDown(with: event)
            return
        }
        guard !isGestureActive else {
            super.keyDown(with: event)
            return
        }
        isGestureActive = true
        onEditingChanged?(true)
        super.keyDown(with: event)
        onEditingChanged?(false)
        isGestureActive = false
    }
}

/// The cell that owns hit geometry. Drawing lives on the slider, but NSSlider
/// routes mouse/track and thumb placement through the cell, so geometry here
/// must match the slider's own (they share `PanelLevelSliderMetrics`).
final class PanelLevelSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {}
    override func drawKnob(_ rect: NSRect) {}

    override var trackRect: NSRect {
        controlView?.bounds ?? super.trackRect
    }

    override func knobRect(flipped: Bool) -> NSRect {
        guard let slider = controlView as? PanelLevelSliderView else {
            return super.knobRect(flipped: flipped)
        }
        let center = slider.knobCenter(in: slider.bounds)
        let radius = PanelLevelSliderMetrics.thumbRadius
        return NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
}