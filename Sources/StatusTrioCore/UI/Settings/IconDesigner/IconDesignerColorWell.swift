import AppKit
import SwiftUI

struct IconDesignerColorWell: NSViewRepresentable {
    @Binding var selection: Color
    let onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TransactionColorWell {
        NSColorPanel.shared.showsAlpha = true
        let well = TransactionColorWell(frame: .zero)
        well.coordinator = context.coordinator
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.color = NSColor(selection)
        well.isBordered = true
        context.coordinator.observePanelClose()
        return well
    }

    func updateNSView(_ well: TransactionColorWell, context: Context) {
        context.coordinator.parent = self
        let color = NSColor(selection)
        if !well.color.isEqual(color) { well.color = color }
    }

    static func dismantleNSView(_ well: TransactionColorWell, coordinator: Coordinator) {
        coordinator.finishGesture()
        coordinator.removeObserver()
        well.coordinator = nil
    }

    final class TransactionColorWell: NSColorWell {
        weak var coordinator: Coordinator?

        override func mouseDown(with event: NSEvent) {
            NSColorPanel.shared.showsAlpha = true
            coordinator?.beginGesture()
            super.mouseDown(with: event)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: IconDesignerColorWell
        private var isEditing = false

        init(_ parent: IconDesignerColorWell) { self.parent = parent }

        func beginGesture() {
            guard !isEditing else { return }
            isEditing = true
            parent.onEditingChanged(true)
        }

        func finishGesture() {
            guard isEditing else { return }
            isEditing = false
            parent.onEditingChanged(false)
        }

        func observePanelClose() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(colorPanelWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: NSColorPanel.shared
            )
        }

        func removeObserver() {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: NSColorPanel.shared)
        }

        @objc func colorPanelWillClose(_ notification: Notification) {
            finishGesture()
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            if !isEditing { beginGesture() }
            parent.selection = Color(nsColor: sender.color)
        }
    }
}
