/// Shared mirror of the power-helper protocol feature levels. Kept outside
/// `PowerHelperProtocol` so shared controllers can gate helper features without
/// importing the Direct-only module. Values must match
/// `PowerHelperProtocolVersion` in Sources/PowerHelperProtocol.
enum PowerHelperFeatureVersion {
    static let lowPowerMode = 1
    static let highPowerMode = 2
    static let disableSleep = 3
}
