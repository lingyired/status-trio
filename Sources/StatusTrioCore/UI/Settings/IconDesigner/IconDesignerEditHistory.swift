import Foundation

struct IconDesignerEditHistory {
    private struct Entry {
        let before: IconDesignerEditSnapshot
        let after: IconDesignerEditSnapshot
    }

    private let limit: Int
    private var entries: [Entry] = []

    init(limit: Int = 64) {
        self.limit = max(0, limit)
    }

    var count: Int { entries.count }

    mutating func record(before: IconDesignerEditSnapshot, after: IconDesignerEditSnapshot) {
        guard before != after, limit > 0 else { return }
        entries.append(Entry(before: before, after: after))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    mutating func undo(current: IconDesignerEditSnapshot) -> IconDesignerEditSnapshot? {
        guard let entry = entries.last, current == entry.after else {
            if !entries.isEmpty { entries.removeAll(keepingCapacity: true) }
            return nil
        }
        entries.removeLast()
        return entry.before
    }

    mutating func coalesceLast(after snapshot: IconDesignerEditSnapshot) -> Bool {
        guard let last = entries.last else { return false }
        entries[entries.count - 1] = Entry(before: last.before, after: snapshot)
        return true
    }

    mutating func invalidateForExternalChange() {
        entries.removeAll(keepingCapacity: true)
    }
}
