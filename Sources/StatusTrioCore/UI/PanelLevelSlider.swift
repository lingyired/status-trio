import AppKit
import SwiftUI

/// Shared geometry between the AppKit drawing and the inline label so the
/// painted track/thumb and the label position always agree.
enum PanelLevelSliderMetrics {
    /// Overall control height on screen.
    static let controlHeight: CGFloat = 30
    /// Shorter height used by the volume and mic rows so those two sliders sit
    /// tighter vertically while the brightness rows keep `controlHeight`.
    static let compactSlotHeight: CGFloat = 20
    /// Slim capsule height for compact (volume/mic) rows (matches the system
    /// small slider track, 4pt).
    static let compactBarHeight: CGFloat = 4
    /// Visible capsule height for rows whose label lives inside the capsule.
    static let barHeight: CGFloat = 13
    /// Thumb height; the pill keeps this height in every state.
    static let thumbDiameter: CGFloat = 16
    /// Half the thumb height, kept for the legacy label-layout math.
    static var thumbRadius: CGFloat { thumbDiameter / 2 }
    /// Thumb shape: a horizontal rounded rectangle (capsule), matching the
    /// system slider knob, used in both the solid and Liquid Glass states.
    static var thumbSize: CGSize {
        CGSize(width: 20, height: thumbDiameter)
    }
    static var thumbHalfWidth: CGFloat { thumbSize.width / 2 }
    static var thumbCornerRadius: CGFloat { thumbSize.height / 2 }
    static var glassThumbSize: CGSize { thumbSize }
    /// Distance kept from the capsule's leading/trailing edge so the pill never
    /// overhangs the track at 0% / 100%.
    static var horizontalInset: CGFloat { thumbHalfWidth }
    static var barCornerRadius: CGFloat { barHeight / 2 }

    /// Inline label inset from the capsule's leading edge.
    static let labelLeadingInset: CGFloat = 12
    /// Gap kept between the thumb and the inline label.
    static let labelGap: CGFloat = 7
    /// Font used by the inline label.
    static let labelFontSize: CGFloat = 8
    /// How long the label takes to move between the two sides.
    static let labelAnimationDuration: TimeInterval = 0.16
    /// How long a programmatic value change (wheel, system echo) takes to glide
    /// to its target instead of jumping. Kept short so it still feels attached
    /// to the gesture.
    static let valueAnimationDuration: TimeInterval = 0.11
    /// Room reserved around the knob raster for its baked shadow.
    static let knobRasterMargin: CGFloat = 6

    /// Thumb centre X for a value in 0...1 across the whole capsule.
    static func thumbCenterX(for value: Double, width: CGFloat) -> CGFloat {
        let clamped = Double(min(1, max(0, value)))
        return horizontalInset + CGFloat(clamped) * max(0, width - horizontalInset * 2)
    }

    /// Fill width for a value in 0...1 while the thumb is drawn.
    ///
    /// The fill stops at the thumb's centre; the thumb itself covers the rest of
    /// the way to the capsule edge. Painting past the centre would poke out above
    /// and below the circle, because the 18pt thumb is taller than the 4–13pt
    /// capsule and its silhouette narrows near the capsule's top/bottom edges
    /// (#359).
    static func coveredFillWidth(for value: Double, width: CGFloat) -> CGFloat {
        let barWidth = max(0, width)
        return min(barWidth, max(0, thumbCenterX(for: value, width: barWidth)))
    }

    /// Fill width for a value in 0...1 when no thumb is drawn.
    ///
    /// At rest the thumb is hidden, so the fill alone must show the value across
    /// the whole capsule: a full value has to reach the right edge instead of
    /// stopping one radius short (#359). Straight value-proportional width keeps
    /// 0/50/99/100% honest.
    static func restingFillWidth(for value: Double, width: CGFloat) -> CGFloat {
        let barWidth = max(0, width)
        let clamped = CGFloat(min(1, max(0, value)))
        return min(barWidth, max(0, barWidth * clamped))
    }

    static var labelFont: NSFont {
        .systemFont(ofSize: labelFontSize, weight: .medium)
    }
}

/// Frozen track geometry for one live pointer/keyboard gesture.
///
/// `NSSliderCell` recomputes the tracked value from its `trackRect` on every
/// event, and this control's `trackRect` is the whole control bounds. If SwiftUI
/// re-lays the row out while the mouse is down, the live width can briefly
/// collapse; the native mapping then divides by ~0, and Swift's
/// `min(1, max(0, NaN))` yields `0` (while `+inf` yields `1`), so the control
/// wrote alternating 0/1 brightness values to the display (#331). Snapshotting
/// the rect when the gesture starts keeps the mapping stable for the whole
/// gesture; outside a gesture the live bounds still drive hit-testing as before.
struct PanelLevelSliderTrackingGeometry: Equatable {
    private(set) var isTracking = false
    private var lockedRect: NSRect?
    private(set) var liveRect: NSRect

    init(liveRect: NSRect = .zero) {
        self.liveRect = liveRect
    }

    /// The rect `NSSliderCell` should map pointer positions against.
    var trackRect: NSRect {
        if isTracking, let lockedRect { return lockedRect }
        return liveRect
    }

    mutating func updateLiveRect(_ rect: NSRect) {
        liveRect = rect
    }

    /// Starts a gesture, freezing the current geometry when it is usable. A
    /// degenerate live rect is not frozen; it keeps following the live bounds
    /// until they become valid (a pointer gesture cannot normally start there).
    mutating func begin() {
        isTracking = true
        lockedRect = (liveRect.width > 1 && liveRect.height > 1) ? liveRect : nil
    }

    mutating func end() {
        isTracking = false
        lockedRect = nil
    }
}

/// Picks readable ink for the inline label drawn on top of the filled capsule.
/// The fill can be a user-chosen colour (#359), so contrast is derived from the
/// fill's luminance instead of assuming the fill matches the panel appearance.
enum PanelLevelSliderColorContrast {
    /// WCAG relative luminance of an sRGB colour (0 = black, 1 = white).
    static func relativeLuminance(of color: NSColor) -> CGFloat? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.039_28
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgb.redComponent)
            + 0.7152 * linear(srgb.greenComponent)
            + 0.0722 * linear(srgb.blueComponent)
    }

    /// Ink that stays readable on `fillColor`. Chooses whichever of white or
    /// black yields the higher WCAG contrast; falls back to the panel's
    /// appearance if the colour cannot be converted to sRGB.
    static func textColor(forFill fillColor: NSColor, isDarkAppearance: Bool) -> NSColor {
        guard let luminance = relativeLuminance(of: fillColor) else {
            return isDarkAppearance
                ? NSColor.black.withAlphaComponent(0.82)
                : NSColor.white.withAlphaComponent(0.95)
        }
        let whiteContrast = 1.05 / (luminance + 0.05)
        let blackContrast = (luminance + 0.05) / 0.05
        return blackContrast >= whiteContrast
            ? NSColor.black.withAlphaComponent(0.82)
            : NSColor.white.withAlphaComponent(0.95)
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
        let attrs: [NSAttributedString.Key: Any] = [.font: PanelLevelSliderMetrics.labelFont]
        return (text as NSString).size(withAttributes: attrs).width
    }

    /// Fixed leading frame used by the panel: the label never follows the thumb,
    /// so the fill can split it mid-glyph. The draw paints the text twice and
    /// clips an inverted copy to the filled capsule. Truncates at the capsule's
    /// trailing inset so it stays inside the rounded ends.
    static func fixedFrame(controlWidth: CGFloat) -> Frame {
        let available = max(
            0,
            controlWidth - PanelLevelSliderMetrics.labelLeadingInset
                - PanelLevelSliderMetrics.horizontalInset
        )
        return Frame(
            side: .leading,
            originX: PanelLevelSliderMetrics.labelLeadingInset,
            width: available
        )
    }

    /// Decides the parked side. The leading (filled) side always wins when the
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
    var tint: Color = .primary
    var accessibilityLabel: String? = nil
    var accessibilityValue: String? = nil
    var accessibilityHint: String? = nil
    var onEditingChanged: (Bool) -> Void = { _ in }
    /// Overall control height on screen. The panel's default is 30; the volume
    /// and mic rows opt into a shorter control while the brightness rows keep
    /// the default.
    var height: CGFloat = PanelLevelSliderMetrics.controlHeight
    /// Visible capsule (bar) height. Standard rows use the metric default; the
    /// compact volume/mic rows opt into a slimmer capsule. `nil` falls back to
    /// the metric default.
    var barHeight: CGFloat = PanelLevelSliderMetrics.barHeight

    @Environment(\.panelCardSurfaceStyle) private var cardSurfaceStyle
    /// True while a pointer drag is in flight; drives the Liquid Glass thumb.
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            Representable(
                isEnabled: isEnabled,
                tint: tint,
                currentValue: value,
                label: label,
                accessibilityLabel: accessibilityLabel,
                accessibilityValue: accessibilityValue,
                accessibilityHint: accessibilityHint,
                onValueChanged: { newValue in
                    value = newValue
                },
                onEditingChanged: { editing in
                    isDragging = editing
                    onEditingChanged(editing)
                },
                height: height,
                barHeight: barHeight,
                hidesKnob: showsGlassThumb
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: height)
        // Accessibility lives on the native NSSlider so VoiceOver sees one
        // adjustable control with the same label/value the old Slider exposed.
    }

    /// While the pointer drags on a native-glass panel, the AppKit view swaps
    /// its solid knob for an `NSGlassEffectView` thumb (#368 follow-up). The
    /// glass lives in the AppKit hierarchy so it is not occluded by the track.
    private var showsGlassThumb: Bool {
        cardSurfaceStyle == .glass
            && PanelBackgroundStyle.isLiquidGlassAvailable
            && isDragging
    }
}

private extension PanelLevelSlider {
    struct Representable: NSViewRepresentable {
        let isEnabled: Bool
        let tint: Color
        let currentValue: Double
        let label: String?
        let accessibilityLabel: String?
        let accessibilityValue: String?
        let accessibilityHint: String?
        let onValueChanged: (Double) -> Void
        let onEditingChanged: (Bool) -> Void
        let height: CGFloat
        let barHeight: CGFloat
        let hidesKnob: Bool

        func makeNSView(context: Context) -> PanelLevelSliderView {
            let slider = PanelLevelSliderView()
            slider.onValueChanged = onValueChanged
            slider.onEditingChanged = onEditingChanged
            slider.isEnabled = isEnabled
            slider.designHeight = height
            slider.barHeight = barHeight
            slider.hidesKnob = hidesKnob
            slider.doubleValue = clamped(currentValue)
            slider.setLabel(label, animated: false)
            applyAccessibility(to: slider)
            return slider
        }

        func updateNSView(_ nsView: PanelLevelSliderView, context: Context) {
            nsView.isEnabled = isEnabled
            nsView.fillColor = NSColor(tint)
            nsView.designHeight = height
            nsView.barHeight = barHeight
            nsView.hidesKnob = hidesKnob
            nsView.onValueChanged = onValueChanged
            nsView.onEditingChanged = onEditingChanged
            nsView.setLabel(label, animated: true)
            applyAccessibility(to: nsView)
            // Mirror external draft changes into the native control. While the
            // pointer tracks, AppKit already owns the position and the draft is
            // deliberately behind (reports are throttled), so never overwrite
            // the gesture; a late system echo outside a drag applies normally
            // (the panel-level state owns echo suppression).
            if !nsView.isTracking {
                // A rebuilt row gets a burst of initial values; snap them until
                // the row settles. Later programmatic changes (wheel notches,
                // system echoes) glide so they read as continuous motion.
                let animated = nsView.shouldAnimateProgrammaticChange(
                    at: ProcessInfo.processInfo.systemUptime
                )
                nsView.setProgrammaticValue(clamped(currentValue), animated: animated)
            }
            nsView.refreshLabel(animated: true)
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
///
/// The optional label is drawn with AppKit instead of a SwiftUI `Text` overlay:
/// drag transactions must never involve the text system (selection handles /
/// focus), and the short side-switch animation is driven by a bounded timer.
final class PanelLevelSliderView: NSSlider {
    var onValueChanged: ((Double) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    var fillColor: NSColor = .labelColor {
        didSet {
            if !fillColor.isEqual(oldValue) { invalidateRaster() }
        }
    }

    /// The panel's design height for this control. The volume and mic rows use
    /// a shorter slot than the brightness rows.
    var designHeight: CGFloat = PanelLevelSliderMetrics.controlHeight
    /// Visible capsule height for this control. Compact rows pass a slim value
    /// so the blue capsule reads shorter than the standard rows. Repaints the
    /// cached track/fill bitmaps when the height changes (the #368 thickness
    /// toggle can flip it live), otherwise a stale fill would be drawn thin
    /// inside the newly taller capsule.
    var barHeight: CGFloat = PanelLevelSliderMetrics.barHeight {
        didSet {
            if barHeight != oldValue { invalidateRaster() }
        }
    }
    private var barCornerRadius: CGFloat { barHeight / 2 }

    /// When true the native solid knob is skipped and an `NSGlassEffectView`
    /// thumb is layered on during a drag on a Liquid Glass panel (#368).
    var hidesKnob: Bool = false {
        didSet {
            if hidesKnob != oldValue {
                syncGlassKnob()
                needsDisplay = true
            }
        }
    }

    /// The Liquid Glass thumb shown while dragging on a glass panel, if any.
    private var glassKnobView: NSView?

    /// Creates/removes and repositions the glass thumb to match the knob. Called
    /// from the SwiftUI update, layout, and drawing so it follows the drag.
    private func syncGlassKnob(createIfNeeded: Bool = true) {
        guard hidesKnob else {
            glassKnobView?.removeFromSuperview()
            glassKnobView = nil
            return
        }
        guard #available(macOS 26.0, *) else { return }
        if glassKnobView == nil, createIfNeeded {
            // A horizontal rounded rectangle (capsule) like the system slider
            // thumb; the glass is clipped to that shape so it reads as a pill
            // instead of the bare NSGlassEffectView lens.
            let container = NSView()
            container.wantsLayer = true
            container.layer?.masksToBounds = true
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.autoresizingMask = [.width, .height]
            container.addSubview(glass)
            container.autoresizingMask = []
            addSubview(container)
            glassKnobView = container
        }
        guard let glassKnobView else { return }
        let center = knobCenter(in: bounds)
        let size = PanelLevelSliderMetrics.glassThumbSize
        let frame = NSRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        if glassKnobView.frame != frame {
            glassKnobView.frame = frame
            glassKnobView.layer?.cornerRadius = size.height / 2
            for subview in glassKnobView.subviews {
                subview.frame = NSRect(origin: .zero, size: size)
                (subview as? NSGlassEffectView)?.cornerRadius = size.height / 2
            }
        }
    }

    private var rasterGeneration = 0
    private var rasterBuiltGeneration = -1
    private var trackImage: NSImage?
    private var fillImage: NSImage?
    private var knobImage: NSImage?

    private var labelText: String?
    private var labelTextWidth: CGFloat = 0
    private var labelOriginX: CGFloat = 0
    private var labelSide: PanelLevelSliderLabelLayout.Side?
    private var labelAnimation: LabelAnimation?
    private var labelAnimationTimer: Timer?

    private struct LabelAnimation {
        var fromX: CGFloat
        var toX: CGFloat
        let startTime: TimeInterval
        var side: PanelLevelSliderLabelLayout.Side
    }

    private struct ValueAnimation {
        var fromValue: Double
        var toValue: Double
        let startTime: TimeInterval
    }

    private var valueAnimation: ValueAnimation?
    private var valueAnimationTimer: Timer?
    /// Programmatic value changes snap until this uptime, so the burst of
    /// initial values a rebuilt row receives (draft default 0, then the real
    /// state) lands without gliding from 0. Set when the view enters a window.
    var animateProgrammaticChangesAfter: TimeInterval = .greatestFiniteMagnitude

    func shouldAnimateProgrammaticChange(at time: TimeInterval) -> Bool {
        // Never glide while the view is detached or still settling: a row that
        // is being rebuilt receives its real value before it enters the window.
        guard window != nil else { return false }
        return time >= animateProgrammaticChangesAfter
    }

    /// Marks tracking session boundaries so `mouseDown`/`mouseUp` around a
    /// super call always pair, including for keyboard navigation.
    private var isGestureActive = false

    /// Frozen track geometry for the current gesture (see
    /// `PanelLevelSliderTrackingGeometry`). Outside a gesture it mirrors the
    /// live bounds, so the value mapping and hit-testing stay unchanged.
    private var trackingGeometry = PanelLevelSliderTrackingGeometry()
    private var currentGestureID = "idle"

    /// The rect `NSSliderCell` maps pointer positions against. While a gesture
    /// is live this is the geometry frozen at gesture start, so a mid-gesture
    /// layout change cannot drag the value. It falls back to the live bounds
    /// when the frozen/live rect is still degenerate.
    var effectiveTrackRect: NSRect {
        let rect = trackingGeometry.trackRect
        if rect.width > 1, rect.height > 1 { return rect }
        if bounds.width > 1, bounds.height > 1 {
            return NSRect(origin: .zero, size: bounds.size)
        }
        return rect
    }

    var effectiveTrackWidth: CGFloat { max(0, effectiveTrackRect.width) }

    func knobCenter(forWidth width: CGFloat) -> NSPoint {
        let x = PanelLevelSliderMetrics.thumbCenterX(for: clampedDoubleValue, width: width)
        return NSPoint(x: x, y: bounds.midY)
    }

    /// Freezes the track geometry when a pointer/keyboard gesture starts.
    /// Internal (not private) so deterministic tests can drive the freeze
    /// without a live AppKit event loop.
    func startGestureTracking() {
        trackingGeometry.updateLiveRect(bounds)
        trackingGeometry.begin()
        currentGestureID = String(UUID().uuidString.prefix(8))
        PanelBrightnessDiagnostics.event(
            "NSSlider",
            currentGestureID,
            "gestureStart bounds=\(formatSize(bounds.size)) track=\(formatSize(effectiveTrackRect.size)) value=\(clampedDoubleValue)"
        )
    }

    private func endGestureTracking() {
        PanelBrightnessDiagnostics.event(
            "NSSlider",
            currentGestureID,
            "gestureEnd bounds=\(formatSize(bounds.size)) value=\(clampedDoubleValue)"
        )
        trackingGeometry.end()
        currentGestureID = "idle"
    }

    private func formatSize(_ size: NSSize) -> String {
        String(format: "%.1fx%.1f", Double(size.width), Double(size.height))
    }

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

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow != nil {
            // Rebuilt rows receive their initial values right after this; snap
            // them instead of gliding from the local default.
            animateProgrammaticChangesAfter =
                ProcessInfo.processInfo.systemUptime + 0.35
        }
        if newWindow == nil {
            animateProgrammaticChangesAfter = .greatestFiniteMagnitude
            stopLabelAnimationTimer()
            stopValueAnimationTimer()
            // If the control is torn down mid-gesture (row rebuilt, panel
            // closed), end the gesture cleanly instead of leaving the panel
            // stuck in an editing state or holding frozen geometry.
            if isGestureActive {
                pendingReportedValue = nil
                isGestureActive = false
                onEditingChanged?(false)
                endGestureTracking()
            }
        }
    }

    override var isFlipped: Bool { true }

    /// NSSlider reports a small intrinsic height (16pt). The panel capsule is
    /// taller, so report the design height; the SwiftUI frame then fills it and
    /// the ready-drawn capsule is vertically centred with the row's glyphs.
    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: designHeight
        )
    }

    // MARK: Geometry shared with the cell.

    var clampedDoubleValue: Double {
        min(1, max(0, doubleValue))
    }


    /// Maps a view-space x to a 0...1 value using the same thumb travel as the
    /// drawing, so a track click lands the thumb where the pointer did.
    func value(forPointX x: CGFloat) -> Double {
        let width = effectiveTrackWidth
        let inset = PanelLevelSliderMetrics.horizontalInset
        let usable = width - inset * 2
        guard usable > 0 else { return clampedDoubleValue }
        let clampedX = min(width - inset, max(inset, x))
        return Double((clampedX - inset) / usable)
    }

    /// Whether a click started on the knob itself (a drag) rather than on the
    /// empty track (a jump that should glide).
    private func isPointOnThumb(_ point: NSPoint) -> Bool {
        let center = knobCenter(in: bounds)
        let size = PanelLevelSliderMetrics.thumbSize
        let dx = abs(point.x - center.x)
        let dy = abs(point.y - center.y)
        return dx <= size.width / 2 && dy <= size.height / 2
    }

    func barRect(in bounds: NSRect) -> NSRect {
        // The capsule spans the full control width so its leading edge lines up
        // with the row's other components; the thumb still travels between the
        // rounded ends (centre inset by its radius).
        let y = (bounds.height - barHeight) / 2
        return NSRect(
            x: 0,
            y: y,
            width: max(0, bounds.width),
            height: barHeight
        )
    }

    func knobCenter(in bounds: NSRect) -> NSPoint {
        let x = PanelLevelSliderMetrics.thumbCenterX(
            for: clampedDoubleValue,
            width: bounds.width
        )
        return NSPoint(x: x, y: bounds.midY)
    }

    // MARK: Label configuration.

    func setLabel(_ text: String?, animated: Bool) {
        let changed = text != labelText
        labelText = text
        if changed {
            labelTextWidth = text.map { PanelLevelSliderLabelLayout.textWidth($0) } ?? 0
        }
        if changed {
            labelAnimation = nil
            stopLabelAnimationTimer()
            labelSide = nil
        }
        refreshLabel(animated: animated)
    }

    func refreshLabel(animated: Bool) {
        // The panel pins the label to the leading edge instead of sliding it
        // around the thumb, so the fill can split it mid-glyph (#368). The
        // draw paints the text twice and clips an inverted copy to the fill.
        labelAnimation = nil
        stopLabelAnimationTimer()
        guard labelText != nil, bounds.width > 0 else {
            labelSide = nil
            needsDisplay = true
            return
        }
        let frame = PanelLevelSliderLabelLayout.fixedFrame(controlWidth: bounds.width)
        labelOriginX = frame.originX
        labelSide = frame.side
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        trackingGeometry.updateLiveRect(bounds)
        refreshLabel(animated: false)
        syncGlassKnob()
    }

    // MARK: Label animation.

    private func currentLabelOriginX() -> CGFloat {
        guard let animation = labelAnimation else { return labelOriginX }
        let elapsed = ProcessInfo.processInfo.systemUptime - animation.startTime
        let progress = min(1, max(0, elapsed / PanelLevelSliderMetrics.labelAnimationDuration))
        // easeInOut
        let eased = progress < 0.5
            ? 2 * progress * progress
            : 1 - pow(-2 * progress + 2, 2) / 2
        return animation.fromX + (animation.toX - animation.fromX) * CGFloat(eased)
    }

    private func startLabelAnimationTimerIfNeeded() {
        guard labelAnimationTimer == nil else { return }
        let timer = Timer(
            timeInterval: Self.animationFrameInterval,
            repeats: true
        ) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.needsDisplay = true
            if let animation = self.labelAnimation {
                let elapsed = ProcessInfo.processInfo.systemUptime - animation.startTime
                if elapsed >= PanelLevelSliderMetrics.labelAnimationDuration {
                    self.labelOriginX = animation.toX
                    self.labelAnimation = nil
                    self.stopLabelAnimationTimer()
                }
            }
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        labelAnimationTimer = timer
    }

    private func stopLabelAnimationTimer() {
        labelAnimationTimer?.invalidate()
        labelAnimationTimer = nil
    }

    // MARK: Value animation.

    /// Applies a programmatic value. `animated == false` snaps: used for the
    /// first value a freshly created view receives, so returning from a detail
    /// page cannot glide from 0 to the restored level.
    func setProgrammaticValue(_ target: Double, animated: Bool) {
        guard target.isFinite else { return }
        if animated {
            animateValue(to: target)
            return
        }
        valueAnimation = nil
        stopValueAnimationTimer()
        doubleValue = min(1, max(0, target))
        refreshLabel(animated: false)
        needsDisplay = true
    }

    /// Eases the drawn position toward a programmatic target. Drags never use
    /// this — the pointer owns the position while `isTracking` — so only wheel
    /// and system-echo updates glide.
    func animateValue(to target: Double) {
        guard target.isFinite else { return }
        let target = min(1, max(0, target))
        if let animation = valueAnimation,
           abs(animation.toValue - target) < 0.000_1 {
            return
        }
        if abs(clampedDoubleValue - target) <= 0.000_1 {
            valueAnimation = nil
            stopValueAnimationTimer()
            doubleValue = target
            refreshLabel(animated: true)
            needsDisplay = true
            return
        }

        let from = currentDisplayedValue()
        valueAnimation = ValueAnimation(
            fromValue: from,
            toValue: target,
            startTime: ProcessInfo.processInfo.systemUptime
        )
        doubleValue = from
        startValueAnimationTimerIfNeeded()
        needsDisplay = true
    }

    /// Glides the drawn thumb from an explicit start to the target. Used for a
    /// track click: the model already holds the target, but easing the pixels
    /// across makes the change read as motion instead of a snap. Drags never
    /// use this — the pointer owns the position while tracking.
    func animateValue(from start: Double, to target: Double) {
        guard start.isFinite, target.isFinite else { return }
        let from = min(1, max(0, start))
        let to = min(1, max(0, target))
        guard abs(to - from) > 0.000_1 else {
            doubleValue = to
            refreshLabel(animated: true)
            needsDisplay = true
            return
        }
        valueAnimation = ValueAnimation(
            fromValue: from,
            toValue: to,
            startTime: ProcessInfo.processInfo.systemUptime
        )
        doubleValue = from
        startValueAnimationTimerIfNeeded()
        refreshLabel(animated: true)
        needsDisplay = true
    }

    /// Stops any in-flight glide and leaves the native value where it is. Used
    /// when a pointer/keyboard gesture takes over the control.
    func cancelValueAnimation() {
        valueAnimation = nil
        stopValueAnimationTimer()
    }

    private func currentDisplayedValue() -> Double {
        guard let animation = valueAnimation else { return clampedDoubleValue }
        let elapsed = ProcessInfo.processInfo.systemUptime - animation.startTime
        let progress = min(1, max(0, elapsed / PanelLevelSliderMetrics.valueAnimationDuration))
        return animation.fromValue + (animation.toValue - animation.fromValue) * Self.easeOut(progress)
    }

    /// Drives both the value and label animations. 120 Hz tracks ProMotion
    /// displays and halves the per-frame step on 60 Hz panels; zero tolerance
    /// stops the run loop from coalescing ticks into a choppier cadence.
    private static let animationFrameInterval: TimeInterval = 1.0 / 120.0

    private func startValueAnimationTimerIfNeeded() {
        guard valueAnimationTimer == nil else { return }
        let timer = Timer(
            timeInterval: Self.animationFrameInterval,
            repeats: true
        ) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.stepValueAnimation()
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        valueAnimationTimer = timer
    }

    private func stepValueAnimation() {
        guard let animation = valueAnimation else {
            stopValueAnimationTimer()
            return
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - animation.startTime
        let progress = min(1, max(0, elapsed / PanelLevelSliderMetrics.valueAnimationDuration))
        let value = animation.fromValue
            + (animation.toValue - animation.fromValue) * Self.easeOut(progress)
        doubleValue = value
        refreshLabel(animated: true)
        needsDisplay = true
        if progress >= 1 {
            doubleValue = animation.toValue
            valueAnimation = nil
            stopValueAnimationTimer()
            refreshLabel(animated: true)
            needsDisplay = true
        }
    }

    private func stopValueAnimationTimer() {
        valueAnimationTimer?.invalidate()
        valueAnimationTimer = nil
    }

    /// Cubic ease-out: quick initial movement that settles gently on the target.
    private static func easeOut(_ progress: Double) -> Double {
        1 - pow(1 - min(1, max(0, progress)), 3)
    }

    // MARK: Drawing.

    /// Whether the slider currently owns a pointer/keyboard gesture.
    var isTracking: Bool { isGestureActive }

    /// Whether the pointer is over the control. The thumb is only painted while
    /// the pointer is inside (matching the macOS 26 slider) or a gesture owns
    /// the control, so it stays visible for the whole drag.
    private var isHovering = false
    private var trackingAreaRef: NSTrackingArea?

    var isThumbVisible: Bool { isHovering || isGestureActive }

    func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    /// Reports at most 30 times a second while a gesture is active. The native
    /// control keeps drawing every frame; writing the SwiftUI binding on each
    /// pointer event made the panel hosting view commit a transaction per event
    /// (#263). A final report flushes when the gesture ends.
    private static let minimumReportInterval: TimeInterval = 1.0 / 30.0
    private var lastReportedAt: TimeInterval?
    private var pendingReportedValue: Double?

    @objc func valueDidChange(_ sender: Any?) {
        refreshLabel(animated: true)
        let value = clampedDoubleValue
        guard value.isFinite else {
            // A degenerate track can push NaN/inf through the native mapping;
            // never let it reach the label, the report path, or the hardware.
            PanelBrightnessDiagnostics.event(
                "NSSlider", currentGestureID, "ignoreNonFinite raw=\(doubleValue)"
            )
            return
        }
        guard isGestureActive else {
            PanelBrightnessDiagnostics.event(
                "NSSlider", currentGestureID, "valueDidChange value=\(value)"
            )
            onValueChanged?(value)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastReportedAt, now - lastReportedAt < Self.minimumReportInterval {
            pendingReportedValue = value
            return
        }
        lastReportedAt = now
        pendingReportedValue = nil
        PanelBrightnessDiagnostics.event(
            "NSSlider",
            currentGestureID,
            "report value=\(value) bounds=\(formatSize(bounds.size)) track=\(formatSize(effectiveTrackRect.size))"
        )
        onValueChanged?(value)
    }

    private func flushPendingReport() {
        guard let pendingReportedValue else { return }
        self.pendingReportedValue = nil
        lastReportedAt = nil
        onValueChanged?(pendingReportedValue)
    }

    override func draw(_ dirtyRect: NSRect) {
        ensureRaster()
        syncGlassKnob(createIfNeeded: false)
        let bar = barRect(in: bounds)
        trackImage?.draw(in: bar)

        if isEnabled, clampedDoubleValue > 0.001 {
            // When the thumb is visible it hides the seam, so the fill stops at
            // its centre; when it is hidden the fill must carry the value all the
            // way to the capsule edge (#359).
            let fillWidth = isThumbVisible
                ? PanelLevelSliderMetrics.coveredFillWidth(for: clampedDoubleValue, width: bar.width)
                : PanelLevelSliderMetrics.restingFillWidth(for: clampedDoubleValue, width: bar.width)
            if fillWidth > 0.5, let fillImage {
                fillImage.draw(
                    in: NSRect(x: bar.minX, y: bar.minY, width: fillWidth, height: bar.height),
                    from: NSRect(x: 0, y: 0, width: fillWidth, height: bar.height),
                    operation: .sourceOver,
                    fraction: 1
                )
            }
        }

        drawLabel()

        guard isThumbVisible, !hidesKnob else { return }
        let center = knobCenter(in: bounds)
        let size = PanelLevelSliderMetrics.thumbSize
        let margin = PanelLevelSliderMetrics.knobRasterMargin
        knobImage?.draw(
            in: NSRect(
                x: center.x - size.width / 2 - margin,
                y: center.y - size.height / 2 - margin,
                width: size.width + margin * 2,
                height: size.height + margin * 2
            )
        )
    }

    // MARK: Raster cache

    /// Rebuilds the track, fill and knob bitmaps. Dragging only needs to blit
    /// them at the new position, so the pointer path avoids Core Graphics path
    /// filling and shadow rasterisation on every event (#263).
    func invalidateRaster() {
        rasterGeneration &+= 1
        rasterBuiltGeneration = -1
        needsDisplay = true
    }

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? 2
    }

    private func ensureRaster() {
        guard rasterBuiltGeneration != rasterGeneration, bounds.width > 1, bounds.height > 1 else {
            return
        }
        rasterBuiltGeneration = rasterGeneration
        let scale = backingScale
        let bar = barRect(in: bounds)
        let dark = isDarkAppearance
        let trackColor = dark
            ? NSColor(white: 1.0, alpha: 0.14)
            : NSColor(white: 0.0, alpha: 0.10)
        // Clamp to the actual bar height so a slim compact track stays a true
        // capsule instead of inheriting the taller named-row radius.
        let barRadius = min(barCornerRadius, bar.height / 2)
        let barSize = bar.size

        trackImage = Self.rasterized(size: barSize, scale: scale) { _ in
            let path = NSBezierPath(
                roundedRect: NSRect(origin: .zero, size: barSize),
                xRadius: barRadius,
                yRadius: barRadius
            )
            trackColor.setFill()
            path.fill()
        }
        fillImage = Self.rasterized(size: barSize, scale: scale) { _ in
            let path = NSBezierPath(
                roundedRect: NSRect(origin: .zero, size: barSize),
                xRadius: barRadius,
                yRadius: barRadius
            )
            self.effectiveFillColor.setFill()
            path.fill()
        }

        let thumbSize = PanelLevelSliderMetrics.thumbSize
        let margin = PanelLevelSliderMetrics.knobRasterMargin
        let knobSize = NSSize(
            width: thumbSize.width + margin * 2,
            height: thumbSize.height + margin * 2
        )
        let knobColor: NSColor = isEnabled
            ? (dark ? NSColor.white : NSColor(calibratedWhite: 0.99, alpha: 1))
            : NSColor(white: dark ? 0.55 : 0.8, alpha: 1)
        let knobRadius = PanelLevelSliderMetrics.thumbCornerRadius
        knobImage = Self.rasterized(size: knobSize, scale: scale) { _ in
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = .zero
            shadow.set()
            let path = NSBezierPath(
                roundedRect: NSRect(
                    x: margin,
                    y: margin,
                    width: thumbSize.width,
                    height: thumbSize.height
                ),
                xRadius: knobRadius,
                yRadius: knobRadius
            )
            knobColor.setFill()
            path.fill()
        }
    }

    private static func rasterized(
        size: NSSize,
        scale: CGFloat,
        draw: (NSGraphicsContext) -> Void
    ) -> NSImage? {
        let pixelsWide = max(1, Int((size.width * scale).rounded(.up)))
        let pixelsHigh = max(1, Int((size.height * scale).rounded(.up)))
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelsWide,
                pixelsHigh: pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        draw(context)
        NSGraphicsContext.restoreGraphicsState()
        rep.size = size
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        trackingGeometry.updateLiveRect(bounds)
        if isGestureActive {
            // A layout change during a live gesture is the trigger #331 needs
            // proof of. The frozen track keeps the value stable; log both so a
            // diagnostic run can confirm whether (and when) the width moves.
            PanelBrightnessDiagnostics.event(
                "NSSlider",
                currentGestureID,
                "boundsChangedDuringGesture bounds=\(formatSize(newSize)) frozenTrack=\(formatSize(effectiveTrackRect.size)) value=\(clampedDoubleValue)"
            )
        }
        invalidateRaster()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        invalidateRaster()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        invalidateRaster()
    }

    override var isEnabled: Bool {
        didSet {
            if isEnabled != oldValue { invalidateRaster() }
        }
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private var effectiveFillColor: NSColor {
        isEnabled ? fillColor : NSColor.gray
    }

    private func drawLabel() {
        guard let text = labelText, !text.isEmpty, bounds.width > 0 else { return }
        let frame = PanelLevelSliderLabelLayout.fixedFrame(controlWidth: bounds.width)
        guard frame.isVisible else { return }

        let font = PanelLevelSliderMetrics.labelFont
        let height = ceil(font.ascender - font.descender + font.leading)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        paragraph.alignment = .left
        let rect = NSRect(
            x: frame.originX,
            y: (bounds.height - height) / 2,
            width: frame.width,
            height: height
        )
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]

        func draw(_ color: NSColor) {
            (text as NSString).draw(
                with: rect,
                options: options,
                attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph,
                ]
            )
        }

        guard isEnabled else {
            draw(trackLabelColor)
            return
        }
        let bar = barRect(in: bounds)
        let fillWidth = min(
            bar.width,
            isThumbVisible
                ? PanelLevelSliderMetrics.coveredFillWidth(for: clampedDoubleValue, width: bar.width)
                : PanelLevelSliderMetrics.restingFillWidth(for: clampedDoubleValue, width: bar.width)
        )
        // No fill: the whole label sits on the track.
        guard fillWidth > 0.5 else {
            draw(trackLabelColor)
            return
        }
        // Fill covers the whole capsule: the whole label is inverted.
        if fillWidth >= bar.width - 0.5 {
            draw(filledLabelColor)
            return
        }
        // Split: paint each side once, clipped to its own region, so the edge is
        // crisp and no glyph is drawn twice (which would leave a light halo).
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(
            x: bar.minX,
            y: bar.minY,
            width: fillWidth,
            height: bar.height
        )).addClip()
        draw(filledLabelColor)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(
            x: bar.minX + fillWidth,
            y: bar.minY,
            width: bar.width - fillWidth,
            height: bar.height
        )).addClip()
        draw(trackLabelColor)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Ink for text over the unfilled track (primary label colour).
    private var trackLabelColor: NSColor {
        guard isEnabled else { return .secondaryLabelColor }
        return NSColor.labelColor.withAlphaComponent(0.9)
    }

    /// Ink for text over the filled capsule, derived from the fill's luminance.
    private var filledLabelColor: NSColor {
        PanelLevelSliderColorContrast.textColor(
            forFill: effectiveFillColor,
            isDarkAppearance: isDarkAppearance
        )
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
        cancelValueAnimation()
        let point = convert(event.locationInWindow, from: nil)
        isGestureActive = true
        startGestureTracking()
        onEditingChanged?(true)
        if isPointOnThumb(point) {
            // Pressing the thumb is a drag: the native tracker keeps the value
            // under the pointer, so there is no jump to animate.
            super.mouseDown(with: event)
            finishActiveGesture()
            return
        }
        // Track click: take over the tracking so the model jumps to the clicked
        // value while the drawn thumb eases across, instead of the native snap.
        _ = window?.makeFirstResponder(self)
        let startValue = clampedDoubleValue
        let clickedValue = value(forPointX: point.x)
        onValueChanged?(clickedValue)
        animateValue(from: startValue, to: clickedValue)
        var didDrag = false
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            if !didDrag {
                didDrag = true
                cancelValueAnimation()
            }
            doubleValue = value(forPointX: convert(next.locationInWindow, from: nil).x)
            valueDidChange(nil)
            needsDisplay = true
        }
        finishActiveGesture()
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
        cancelValueAnimation()
        isGestureActive = true
        startGestureTracking()
        onEditingChanged?(true)
        super.keyDown(with: event)
        finishActiveGesture()
    }

    /// Ends the live pointer/keyboard gesture exactly once: flush the throttled
    /// final report, close the editing session, and release the frozen geometry.
    private func finishActiveGesture() {
        guard isGestureActive else { return }
        flushPendingReport()
        onEditingChanged?(false)
        isGestureActive = false
        endGestureTracking()
    }
}

/// The cell that owns hit geometry. Drawing lives on the slider, but NSSlider
/// routes mouse/track and thumb placement through the cell, so geometry here
/// must match the slider's own (they share `PanelLevelSliderMetrics`).
final class PanelLevelSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {}
    override func drawKnob(_ rect: NSRect) {}

    override var trackRect: NSRect {
        guard let slider = controlView as? PanelLevelSliderView else { return super.trackRect }
        return slider.effectiveTrackRect
    }

    override func knobRect(flipped: Bool) -> NSRect {
        guard let slider = controlView as? PanelLevelSliderView else {
            return super.knobRect(flipped: flipped)
        }
        // Use the same frozen/live width `trackRect` reports so the cell's
        // value mapping and the drawn thumb cannot disagree mid-gesture.
        let center = slider.knobCenter(forWidth: slider.effectiveTrackWidth)
        let size = PanelLevelSliderMetrics.thumbSize
        return NSRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
