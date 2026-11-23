import Foundation

/// Store-side stand-in for the Direct-only IOReport `CPUFrequencyReader`.
/// The App Store build cannot link the private IOReport framework, so frequency
/// is always unavailable.
struct CPUFrequencyReader {
    init() {}
    func read(at date: Date) -> CPUFrequencyReading? { nil }
    func reset() {}
}
