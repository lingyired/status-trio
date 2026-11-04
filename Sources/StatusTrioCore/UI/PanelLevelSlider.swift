import AppKit
import SwiftUI

/// Shared geometry between the AppKit drawing and the SwiftUI inline label so
/// the painted track/thumb and the label position always agree.
enum PanelLevelSliderMetrics {
    /// Overall control height on screen.
    static let controlHeight: CGFloat = 30
    /// Visible capsule height.
    static let barHeight: CGFloat = 16
    /// White thumb circle diameter.
    static let thumbDiameter: CGFloat = 18
    static var thumbRadius: CGFloat { thumbDiameter / 2 }
    /// Distance kept from the capsule's leading/trailing edge.
    static var horizontalInset: CGFloat { thumbRadius }
    static var barCornerRadius: CGFloat { barHeight / 2 }

    /// Inline label inset from the capsule's leading edge.
    static let labelLeadingInset: CGFloat = 12
    /// Gap kept between the thumb and the inline label.
    static let labelGap: CGFloat = 7

    /// Thumb centre X for a value in 0...1 across the whole capsule.
    static func thumbCenterX(for value: Double, width: CGFloat) -> CGFloat {
        let clamped = Double(min(1, max(0, value)))
        return horizontalInset + CGFloat(clamped) * max(0, width - horizontalInset * 2)
    }
}

/// Pure layout for the optional inline label: it lives inside the capsule and
/// parks on whichever side of the thumb keeps it fully readable.
enum PanelLevelSliderLabelLayout {
    enum Side: Equatable {
        case leading
        case trailing
    }

    struct Frame: Equatable {
        let side: Side
        let originX: CGFloat
        let width: CGFloat
        var isVisible: Bool { width > 0.5 }
    }

    /// Measured width of the label text using the component's font.
    static func textWidth(_ text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium)
        ]
        return (text as NSString).size(withAttributes: attrs).width
    }

    /// Decides the parked side. The leading (blue) side always wins when the
    /// whole text fits there; only then does the label move to the trailing
    /// side of the thumb, and if neither side fits it truncates on the roomier
    /// one.
    static func side(
        thumbCenterX: CGFloat,
        controlWidth: CGFloat,
        textWidth: CGFloat
    ) -> Side {
        let leading = leadingSpace(thumbCenterX: thumbCenterX)
        let trailing = trailingSpace(
            thumbCenterX: thumbCenterX,
            controlWidth: controlWidth
        )
        if leading >= textWidth { return .leading }
        if trailing >= textWidth { return .trailing }
        return leading >= trailing ? .leading : .trailing
    }

    static func leadingSpace(thumbCenterX: CGFloat) -> CGFloat {
        max(
            0,
            (thumbCenterX - PanelLevelSliderMetrics.thumbRadius
                - PanelLevelSliderMetrics.labelGap)
                - PanelLevelSliderMetrics.labelLeadingInset
        )
    }

    static func trailingSpace(thumbCenterX: CGFloat, controlWidth: CGFloat) -> CGFloat {
        max(
            0,
            (controlWidth - PanelLevelSliderMetrics.labelLeadingInset)
                - (thumbCenterX + PanelLevelSliderMetrics.thumbRadius
                    + PanelLevelSliderMetrics.labelGap)
        )
    }

    /// Where the label is drawn for the chosen side, truncated to the free
    /// space so it can never run under the thumb or the fill.
    static func frame(
        side: Side,
        thumbCenterX: CGFloat,
        controlWidth: CGFloat,
        textWidth: CGFloat
    ) -> Frame {
        switch side {
        case .leading:
            let available = leadingSpace(thumbCenterX: thumbCenterX)
            return Frame(
                side: .leading,
                originX: PanelLevelSliderMetrics.labelLeadingInset,
                width: min(textWidth, available)
            )
        case .trailing:
            let origin = thumbCenterX + PanelLevelSliderMetrics.thumbRadius
                + PanelLevelSliderMetrics.labelGap
            let available = trailingSpace(
                thumbCenterX: thumbCenterX,
                controlWidth: controlWidth
            )
            return Frame(
                side: .trailing,
                originX: origin,
                width: min(textWidth, available)
            )
        }
    }

    /// White ink over the accent fill (leading side), primary over the unfilled
    /// track (trailing side).
    static func usesLightText(side: Side) -> Bool {
        side == .leading
    }
}

/// SwiftUI wrapper exposing the reusable panel level slider.
///
/// The component only owns appearance and basic interaction: produced values
/// are written straight into `value` and editing boundaries are surfaced via
/// `onEditingChanged`. It contains no volume/brightness business logic.
///
/// Vision (macOS inline capture): a 30pt row, fully-rounded capsule, white
/// thumb, accent-filled progress, and an optional single-line label that lives
/// inside the capsule and steps aside when the thumb reaches it.
struct PanelLevelSlider: View {
    @Binding var value: Double
    var label: String? = nil
    var isEnabled: Bool = true
    var tint: Color = .accentColor
    var accessibilityLabel: String? = nil
    var accessibilityValue: String? = nil
    var accessibilityHint: String? = nil
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let centerX = PanelLevelSliderMetrics.thumbCenterX(
                for: value,
                width: width
            )
            let labelSide: PanelLevelSliderLabelLayout.Side = label.map { text in
                PanelLevelSliderLabelLayout.side(
                    thumbCenterX: centerX,
                    controlWidth: width,
                    textWidth: PanelLevelSliderLabelLayout.textWidth(text)
                )
            } ?? .leading
            ZStack(alignment: .leading) {
                Representable(
                    isEnabled: isEnabled,
                    tint: tint,
                    currentValue: value,
                    accessibilityLabel: accessibilityLabel,
                    accessibilityValue: accessibilityValue,
                    accessibilityHint: accessibilityHint,
                    onValueChanged: { newValue in
                        value = newValue
                    },
                    onEditingChanged: onEditingChanged
                )

                if let label {
                    inlineLabel(
                        label,
                        side: labelSide,
                        thumbCenterX: centerX,
                        width: width
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(height: PanelLevelSliderMetrics.controlHeight)
        // Accessibility lives on the native NSSlider so VoiceOver sees one
        // adjustable control with the same label/value the old Slider exposed.
    }

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
            textWidth: PanelLevelSliderLabelLayout.textWidth(text)
        )
        if frame.isVisible {
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(labelColor(side: frame.side))
                .frame(width: frame.width, alignment: .leading)
                .help(text)
                .offset(x: frame.originX, y: 0)
                // Animate only the leading/trailing hand-off; the drag itself
                // must stay frame-synchronous, so this is keyed to the side and
                // not to the continuous value.
                .animation(.easeInOut(duration: 0.16), value: frame.side)
        }
    }

    private func labelColor(side: PanelLevelSliderLabelLayout.Side) -> Color {
        guard isEnabled else { return .primary.opacity(0.55) }
        return PanelLevelSliderLabelLayout.usesLightText(side: side)
            ? Color.white.opacity(0.95)
            : Color.primary.opacity(0.9)
    }
}

private extension PanelLevelSlider {
    struct Representable: NSViewRepresentable {
        let isEnabled: Bool
        let tint: Color
        let currentValue: Double
        let accessibilityLabel: String?
        let accessibilityValue: String?
        let accessibilityHint: String?
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
            slider.setAccessibilityHelp(accessibilityHint)
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
    /// super call always pair, including for keyboard navigation.
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
        // The capsule spans the full control width so its leading edge lines up
        // with the row's other components; the thumb still travels between the
        // rounded ends (centre inset by its radius).
        let y = (bounds.height - PanelLevelSliderMetrics.barHeight) / 2
        return NSRect(
            x: 0,
            y: y,
            width: max(0, bounds.width),
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
            width: min(fillWidth, barRect.width),
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