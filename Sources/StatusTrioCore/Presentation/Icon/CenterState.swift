enum CenterState: Equatable, Hashable, Sendable {
    case symbol(IconSymbolState)
    case text(IconTextState)
}


extension CenterState {
    var normalizedSizePercentageValue: Double? {
        switch self {
        case let .symbol(symbol): symbol.normalizedSizePercentage
        case let .text(text): text.normalizedSizePercentage
        }
    }
}

extension CenterState {
    /// Stable identity of the centre's kind (not its live value), used as part
    /// of the reference-calibration cache key.
    var kindIdentity: String {
        switch self {
        case .symbol: "symbol"
        case .text: "text"
        }
    }
}
