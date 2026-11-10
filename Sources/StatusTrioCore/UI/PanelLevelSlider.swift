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
    /// Slim capsule height for compact (volume/mic) rows.
    static let compactBarHeight: CGFloat = 12
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
    /// Font used by the inline label.
    static let labelFontSize: CGFloat = 9
    /// How long the label takes to move between the two sides.
    static let labelAnimationDuration: TimeInterval = 0.16
    /// Room reserved around the knob raster for its baked shadow.
    static let knobRasterMargin: CGFloat = 6

    /// Thumb centre X for a value in 0...1 across the whole capsule.
    static func thumbCenterX(for value: Double, width: CGFloat) -> CGFloat {
        let clamped = Double(min(1, max(0, value)))
        return horizontalInset + CGFloat(clamped) * max(0, width - horizontalInset * 2)
    }

    static var labelFont: NSFont {
        .systemFont(ofSize: labelFontSize, weight: .medium)
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
    /// Overall control height on screen. The panel's default is 30; the volume
    /// and mic rows opt into a shorter control while the brightness rows keep
    /// the default.
    var height: CGFloat = PanelLevelSliderMetrics.controlHeight
    /// Visible capsule (bar) height. Standard rows use the metric default; the
    /// compact volume/mic rows opt into a slimmer capsule. `nil` falls back to
    /// the metric default.
    var barHeight: CGFloat = PanelLevelSliderMetrics.barHeight

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
                onEditingChanged: onEditingChanged,
                height: height,
                barHeight: barHeight
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: height)
        // Accessibility lives on the native NSSlider so VoiceOver sees one
        // adjustable control with the same label/value the old Slider exposed.
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

        func makeNSView(context: Context) -> PanelLevelSliderView {
            let slider = PanelLevelSliderView()
            slider.onValueChanged = onValueChanged
            slider.onEditingChanged = onEditingChanged
            slider.isEnabled = isEnabled
            slider.designHeight = height
            slider.barHeight = barHeight
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
                let target = clamped(currentValue)
                if abs(nsView.doubleValue - target) > 0.0001 {
                    nsView.doubleValue = target
                    nsView.needsDisplay = true
                }
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
    var fillColor: NSColor = .controlAccentColor {
        didSet {
            if !fillColor.isEqual(oldValue) { invalidateRaster() }
        }
    }

    /// The panel's design height for this control. The volume and mic rows use
    /// a shorter slot than the brightness rows.
    var designHeight: CGFloat = PanelLevelSliderMetrics.controlHeight
    /// Visible capsule height for this control. Compact rows pass a slim value
    /// so the blue capsule reads shorter than the standard rows.
    var barHeight: CGFloat = PanelLevelSliderMetrics.barHeight
    private var barCornerRadius: CGFloat { barHeight / 2 }

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

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopLabelAnimationTimer()
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
        guard labelText != nil, bounds.width > 0 else {
            labelAnimation = nil
            stopLabelAnimationTimer()
            labelSide = nil
            needsDisplay = true
            return
        }
        let textWidth = labelTextWidth
        let centerX = knobCenter(in: bounds).x
        let side = PanelLevelSliderLabelLayout.side(
            thumbCenterX: centerX,
            controlWidth: bounds.width,
            textWidth: textWidth
        )
        let target = PanelLevelSliderLabelLayout.frame(
            side: side,
            thumbCenterX: centerX,
            controlWidth: bounds.width,
            textWidth: textWidth
        )

        if animated, bounds.width > 0, let previousSide = labelSide,
           previousSide != target.side {
            let startX = currentLabelOriginX()
            labelAnimation = LabelAnimation(
                fromX: startX,
                toX: target.originX,
                startTime: ProcessInfo.processInfo.systemUptime,
                side: target.side
            )
            labelSide = target.side
            startLabelAnimationTimerIfNeeded()
        } else if labelAnimation != nil {
            labelAnimation?.toX = target.originX
            labelAnimation?.side = target.side
            labelSide = target.side
            startLabelAnimationTimerIfNeeded()
        } else {
            labelOriginX = target.originX
            labelSide = target.side
        }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        refreshLabel(animated: false)
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
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
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
        RunLoop.main.add(timer, forMode: .common)
        labelAnimationTimer = timer
    }

    private func stopLabelAnimationTimer() {
        labelAnimationTimer?.invalidate()
        labelAnimationTimer = nil
    }

    // MARK: Drawing.

    /// Whether the slider currently owns a pointer/keyboard gesture.
    var isTracking: Bool { isGestureActive }

    /// Reports at most 30 times a second while a gesture is active. The native
    /// control keeps drawing every frame; writing the SwiftUI binding on each
    /// pointer event made the panel hosting view commit a transaction per event
    /// (#263). A final report flushes when the gesture ends.
    private static let minimumReportInterval: TimeInterval = 1.0 / 30.0
    private var lastReportedAt: TimeInterval?
    private var pendingReportedValue: Double?

    @objc func valueDidChange(_ sender: Any?) {
        refreshLabel(animated: true)
        guard isGestureActive else {
            onValueChanged?(clampedDoubleValue)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastReportedAt, now - lastReportedAt < Self.minimumReportInterval {
            pendingReportedValue = clampedDoubleValue
            return
        }
        lastReportedAt = now
        pendingReportedValue = nil
        onValueChanged?(clampedDoubleValue)
    }

    private func flushPendingReport() {
        guard let pendingReportedValue else { return }
        self.pendingReportedValue = nil
        lastReportedAt = nil
        onValueChanged?(pendingReportedValue)
    }

    override func draw(_ dirtyRect: NSRect) {
        ensureRaster()
        let bar = barRect(in: bounds)
        trackImage?.draw(in: bar)

        if isEnabled, clampedDoubleValue > 0.001 {
            let centerX = knobCenter(in: bounds).x
            let fillWidth = min(max(0, centerX - bar.minX), bar.width)
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

        let center = knobCenter(in: bounds)
        let margin = PanelLevelSliderMetrics.knobRasterMargin
        knobImage?.draw(
            in: NSRect(
                x: center.x - PanelLevelSliderMetrics.thumbRadius - margin,
                y: center.y - PanelLevelSliderMetrics.thumbRadius - margin,
                width: PanelLevelSliderMetrics.thumbDiameter + margin * 2,
                height: PanelLevelSliderMetrics.thumbDiameter + margin * 2
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
        let barRadius = barCornerRadius
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

        let diameter = PanelLevelSliderMetrics.thumbDiameter
        let margin = PanelLevelSliderMetrics.knobRasterMargin
        let knobSize = NSSize(width: diameter + margin * 2, height: diameter + margin * 2)
        let knobColor: NSColor = isEnabled
            ? (dark ? NSColor.white : NSColor(calibratedWhite: 0.99, alpha: 1))
            : NSColor(white: dark ? 0.55 : 0.8, alpha: 1)
        knobImage = Self.rasterized(size: knobSize, scale: scale) { _ in
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = .zero
            shadow.set()
            let path = NSBezierPath(
                ovalIn: NSRect(x: margin, y: margin, width: diameter, height: diameter)
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
        let textWidth = labelTextWidth
        let centerX = knobCenter(in: bounds).x
        let frame = PanelLevelSliderLabelLayout.frame(
            side: labelSide ?? PanelLevelSliderLabelLayout.side(
                thumbCenterX: centerX,
                controlWidth: bounds.width,
                textWidth: textWidth
            ),
            thumbCenterX: centerX,
            controlWidth: bounds.width,
            textWidth: textWidth
        )
        guard frame.isVisible else { return }

        let font = PanelLevelSliderMetrics.labelFont
        let height = ceil(font.ascender - font.descender + font.leading)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        paragraph.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: labelColor(side: frame.side),
            .paragraphStyle: paragraph,
        ]
        let rect = NSRect(
            x: currentLabelOriginX(),
            y: (bounds.height - height) / 2,
            width: frame.width,
            height: height
        )
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes
        )
    }

    private func labelColor(side: PanelLevelSliderLabelLayout.Side) -> NSColor {
        guard isEnabled else { return .secondaryLabelColor }
        return PanelLevelSliderLabelLayout.usesLightText(side: side)
            ? NSColor.white.withAlphaComponent(0.95)
            : NSColor.labelColor.withAlphaComponent(0.9)
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
        flushPendingReport()
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
        flushPendingReport()
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
