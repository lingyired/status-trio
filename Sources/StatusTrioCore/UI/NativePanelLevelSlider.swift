import AppKit
import SwiftUI

/// Native thin-track appearance with explicit drag/keyboard edit boundaries so
/// each panel's backend can finish its adjustment when editing ends.
struct NativePanelLevelSlider: NSViewRepresentable {
    @Binding var value: Double
    let isEnabled: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    var accessibilityHint: String? = nil
    let onEditingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> NativePanelLevelSliderControl {
        let slider = NativePanelLevelSliderControl()
        updateNSView(slider, context: context)
        return slider
    }

    func updateNSView(_ slider: NativePanelLevelSliderControl, context: Context) {
        slider.isEnabled = isEnabled
        slider.setAccessibilityLabel(accessibilityLabel)
        slider.setAccessibilityValue(accessibilityValue)
        slider.setAccessibilityHelp(accessibilityHint)
        slider.onValueChanged = { value = $0 }
        slider.onEditingChanged = onEditingChanged
        if !slider.isEditing {
            slider.doubleValue = min(1, max(0, value))
        }
    }
}

final class NativePanelLevelSliderControl: NSSlider {
    var onValueChanged: ((Double) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    private(set) var isEditing = false

    // Match the panel slider's #263 reporting boundary: AppKit owns smooth
    // native drawing while SwiftUI receives at most 30 reports per second.
    // No idle timer is needed; the editing boundary flushes the newest value.
    private static let minimumReportInterval: TimeInterval = 1.0 / 30.0
    private var lastReportedAt: TimeInterval?
    private var pendingReportedValue: Double?

    init() {
        super.init(frame: .zero)
        minValue = 0
        maxValue = 1
        isContinuous = true
        isVertical = false
        sliderType = .linear
        controlSize = .small
        trackFillColor = .secondaryLabelColor
        target = self
        action = #selector(valueChanged)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 30)
    }

    @objc private func valueChanged() {
        let value = min(1, max(0, doubleValue))
        guard isEditing else {
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
        onValueChanged?(value)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, !isEditing else { return }
        beginEditing()
        defer { endEditing() }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        // Tab and Escape keep their normal navigation behavior; only native
        // adjustment keys should create a brightness edit/flush transaction.
        guard Self.adjustmentKeys.contains(event.keyCode), !isEditing else {
            super.keyDown(with: event)
            return
        }
        beginEditing()
        defer { endEditing() }
        super.keyDown(with: event)
    }

    private static let adjustmentKeys: Set<UInt16> = [123, 124, 125, 126, 115, 119, 116, 121]

    private func beginEditing() {
        lastReportedAt = nil
        pendingReportedValue = nil
        isEditing = true
        onEditingChanged?(true)
    }

    private func endEditing() {
        if let pendingReportedValue {
            self.pendingReportedValue = nil
            onValueChanged?(pendingReportedValue)
        }
        lastReportedAt = nil
        isEditing = false
        onEditingChanged?(false)
    }
}
