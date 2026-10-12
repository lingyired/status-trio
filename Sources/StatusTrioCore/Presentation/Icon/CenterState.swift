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
