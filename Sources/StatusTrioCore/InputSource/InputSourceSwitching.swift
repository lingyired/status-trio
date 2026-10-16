import Carbon
import Foundation

/// The outcome of one `TISSelectInputSource` call, kept as a value so the
/// controller can report real failures instead of optimistically marking the
/// target as selected.
enum InputSourceSelectionResult: Equatable, Sendable {
    case selected
    case failed(osStatus: Int32)
}

/// Switches the selected input source. Implementations must only use public
/// TIS API; no key simulation and no private symbols.
protocol InputSourceSwitching {
    func select(id: String) -> InputSourceSelectionResult
}

struct SystemInputSourceSwitcher: InputSourceSwitching {
    func select(id: String) -> InputSourceSelectionResult {
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
              let first = (list as NSArray).firstObject else {
            return .failed(osStatus: Int32(paramErr))
        }

        let source = first as! TISInputSource
        let status = TISSelectInputSource(source)
        return status == noErr ? .selected : .failed(osStatus: status)
    }
}
