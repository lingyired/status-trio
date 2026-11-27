import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A drag payload for the menu-bar element editor. Palette items create a new
/// element; placed items move an existing one (by stable id).
struct MenuBarElementDragPayload: Codable, Transferable, Equatable {
    enum Source: Codable, Equatable {
        case palette(MenuBarElementContent)
        case placed(instanceID: UUID, slot: MenuBarLineSlot, elementID: UUID)
    }

    var source: Source

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

enum MenuBarElementDropTarget: Equatable {
    case line(instanceID: UUID, slot: MenuBarLineSlot, index: Int)
}

/// Pure, index-safe mutations used by drag/drop and by tests. Views never carry
/// this logic; they only build a payload and a target.
enum MenuBarElementMutations {
    /// Applies a drop to `instance`. Returns true when the instance changed.
    static func apply(
        payload: MenuBarElementDragPayload,
        to instance: inout MenuBarInstance,
        target: MenuBarElementDropTarget
    ) -> Bool {
        guard case let .line(instanceID, targetSlot, rawIndex) = target else { return false }
        guard instanceID == instance.id else { return false }
        guard targetSlot == .top || instance.layoutMode == .doubleLine else { return false }

        switch payload.source {
        case .palette(let content):
            let index = clamp(rawIndex, to: currentElements(instance, targetSlot).count)
            var line = currentElements(instance, targetSlot)
            guard line.count < 32 else { return false }
            line.insert(MenuBarElement(content: content), at: index)
            setElements(&instance, line, targetSlot)
            return true

        case .placed(let sourceID, let sourceSlot, let elementID):
            guard sourceID == instance.id else { return false }
            // Single-line mode cannot hold a bottom row.
            guard sourceSlot == .top || instance.layoutMode == .doubleLine else { return false }
            var sourceElements = currentElements(instance, sourceSlot)
            guard let currentIndex = sourceElements.firstIndex(where: { $0.id == elementID }) else { return false }
            let element = sourceElements[currentIndex]

            if sourceSlot == targetSlot {
                var destination = clamp(rawIndex, to: sourceElements.count)
                if destination == currentIndex || destination == currentIndex + 1 { return false }
                sourceElements.remove(at: currentIndex)
                if destination > currentIndex { destination -= 1 }
                sourceElements.insert(element, at: clamp(destination, to: sourceElements.count))
                setElements(&instance, sourceElements, sourceSlot)
                return true
            }

            sourceElements.remove(at: currentIndex)
            var destinationElements = currentElements(instance, targetSlot)
            guard destinationElements.count < 32 else { return false }
            destinationElements.insert(element, at: clamp(rawIndex, to: destinationElements.count))
            setElements(&instance, sourceElements, sourceSlot)
            setElements(&instance, destinationElements, targetSlot)
            return true
        }
    }

    static func currentElements(_ instance: MenuBarInstance, _ slot: MenuBarLineSlot) -> [MenuBarElement] {
        switch slot {
        case .top: return instance.top?.elements ?? []
        case .bottom: return instance.bottom?.elements ?? []
        }
    }

    private static func setElements(_ instance: inout MenuBarInstance, _ elements: [MenuBarElement], _ slot: MenuBarLineSlot) {
        switch slot {
        case .top:
            var line = instance.top ?? MenuBarLine()
            line.elements = elements
            instance.top = line
        case .bottom:
            var line = instance.bottom ?? MenuBarLine()
            line.elements = elements
            instance.bottom = line
        }
    }

    private static func clamp(_ value: Int, to upper: Int) -> Int {
        min(max(0, value), upper)
    }
}
