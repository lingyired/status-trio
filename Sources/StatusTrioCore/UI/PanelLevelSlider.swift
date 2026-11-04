import AppKit
import SwiftUI

/// Shared geometry between the AppKit drawing and the SwiftUI inline label so
/// the painted track/thumb and the label column always agree.
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
    /// Gap kept between the label column and the track's start.
    static let labelGap: CGFloat = 8
    /// A label column may never eat more than half of the capsule, otherwise
    /// the thumb would have no travel left.
    static let maximumLabelFraction: CGFloat = 0.46

    /// Width reserved for the inline label. `preferred` lets a section give
    /// every row the same column width so all tracks start at the same x.
    static func reservedLabelWidth(
        textWidth: CGFloat,
        controlWidth: CGFloat,
        preferred: CGFloat?
    ) -> CGFloat {
        guard textWidth > 0 || (preferred ?? 0) > 0 else { return 0 }
        let candidate = preferred ?? textWidth
        let cap = max(0, controlWidth * maximumLabelFraction)
        return min(max(0, candidate), cap)
    }

    /// X where the thumb's travel begins, leaving the label column free.
    ///
    /// The start accounts for the thumb radius so the thumb's leading edge can
    /// never overlap the label text. Without a label the travel starts at the
    /// capsule's leading inset, matching a plain macOS slider.
    static func trackStartX(
        controlWidth: CGFloat,
        reservedLabelWidth: CGFloat
    ) -> CGFloat {
        guard reservedLabelWidth > 0, controlWidth > 0 else {
            return horizontalInset
        }
        let labelEnd = labelLeadingInset + reservedLabelWidth
        let start = labelEnd + labelGap + thumbRadius
        let latestUsefulStart = max(horizontalInset, controlWidth - horizontalInset)
        return min(start, latestUsefulStart)
    }

    /// Thumb centre X for a value in 0...1, travelling between the track start
    /// and the trailing inset.
    static func thumbCenterX(
        for value: Double,
        width: CGFloat,
        trackStartX: CGFloat
    ) -> CGFloat {
        let clamped = Double(min(1, max(0, value)))
        let start = max(horizontalInset, trackStartX)
        let end = max(start, width - horizontalInset)
        return start + CGFloat(clamped) * (end - start)
    }
}

/// Pure layout for the optional inline label column.
enum PanelLevelSliderLabelLayout {
    /// Measured width of the label text using the component's font.
    static func textWidth(_ text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium)
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
/// Vision (macOS inline capture): a 30pt row, fully-rounded capsule, white
/// thumb, accent-filled progress, and an optional single-line label that owns a
/// fixed column inside the capsule so it always stays fully legible and the
/// thumb never runs into it.
struct PanelLevelSlider: View {
    @Binding var value: Double
    var label: String? = nil
    /// Fixed label column width shared across rows (nil = fit the text).
    var labelColumnWidth: CGFloat? = nil
    var isEnabled: Bool = true
    var tint: Color = .accentColor
    var accessibilityLabel: String? = nil
    var accessibilityValue: String? = nil
    var accessibilityHint: String? = nil
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let textWidth = label.map { PanelLevelSliderLabelLayout.textWidth($0) } ?? 0
            let reserved = label == nil
                ? 0
                : PanelLevelSliderMetrics.reservedLabelWidth(
                    textWidth: textWidth,
                    controlWidth: width,
                    preferred: labelColumnWidth
                )
            let trackStart = PanelLevelSliderMetrics.trackStartX(
                controlWidth: width,
                reservedLabelWidth: reserved
            )
            ZStack(alignment: .leading) {
                Representable(
                    isEnabled: isEnabled,
                    tint: tint,
                    currentValue: value,
                    labelReserve: reserved,
                    accessibilityLabel: accessibilityLabel,
                    accessibilityValue: accessibilityValue,
                    accessibilityHint: accessibilityHint,
                    onValueChanged: { newValue in
                        value = newValue
                    },
                    onEditingChanged: onEditingChanged
                )

                if let label {
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(
                            isEnabled ? Color.primary.opacity(0.9) : Color.primary.opacity(0.55)
                        )
                        .frame(width: reserved, alignment: .leading)
                        .offset(x: PanelLevelSliderMetrics.labelLeadingInset, y: 0)
                        .help(label)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: PanelLevelSliderMetrics.controlHeight)
        // Accessibility lives on the native NSSlider so VoiceOver sees one
        // adjustable control with the same label/value the old Slider exposed.
    }
}

private extension PanelLevelSlider {
    struct Representable: NSViewRepresentable {
        let isEnabled: Bool
        let tint: Color
        let currentValue: Double
        let labelReserve: CGFloat
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
            slider.labelReserve = labelReserve
            slider.doubleValue = clamped(currentValue)
            applyAccessibility(to: slider)
            return slider
        }

        func updateNSView(_ nsView: PanelLevelSliderView, context: Context) {
            nsView.isEnabled = isEnabled
            nsView.fillColor = NSColor(tint)
            nsView.labelReserve = labelReserve
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
    /// Width reserved for an inline label; the track starts after it.
    var labelReserve: CGFloat = 0

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

    func trackStartX(in bounds: NSRect) -> CGFloat {
        PanelLevelSliderMetrics.trackStartX(
            controlWidth: bounds.width,
            reservedLabelWidth: labelReserve
        )
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
            width: bounds.width,
            trackStartX: trackStartX(in: bounds)
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

        let startX = trackStartX(in: bounds)
        // An inline label leaves the leading part of the capsule as a label
        // bay. Draw a slightly recessed groove for the actual travel so the
        // thumb at 0% reads as the groove's start, not a stray control.
        if startX > barRect.minX {
            let grooveRect = NSRect(
                x: startX,
                y: barRect.minY,
                width: max(0, barRect.maxX - startX),
                height: barRect.height
            )
            let grooveColor = isDarkAppearance
                ? NSColor(white: 1.0, alpha: 0.10)
                : NSColor(white: 0.0, alpha: 0.07)
            grooveColor.setFill()
            NSBezierPath(
                roundedRect: grooveRect,
                xRadius: PanelLevelSliderMetrics.barCornerRadius,
                yRadius: PanelLevelSliderMetrics.barCornerRadius
            ).fill()
        }

        guard isEnabled, clampedDoubleValue > 0.001 else { return }
        let centerX = knobCenter(in: bounds).x
        let fillWidth = max(0, centerX - startX)
        guard fillWidth > 0.5 else { return }
        let fillRect = NSRect(
            x: startX,
            y: barRect.minY,
            width: min(fillWidth, barRect.maxX - startX),
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