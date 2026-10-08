import Foundation

/// Normalizes the first OS preference after validating the server's bounded
/// language-tag grammar. Invalid values are omitted before known-language matching.
enum TelemetryLanguageTag {
    static func osLanguageTag(preferred: [String]) -> String? {
        guard let first = preferred.first else { return nil }
        return normalize(first)
    }

    static func normalize(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let normalizedSeparators = rawValue.replacingOccurrences(of: "_", with: "-")
        guard isValid(normalizedSeparators) else { return nil }

        let parts = normalizedSeparators.split(separator: "-").map(String.init)
        let language = parts[0].lowercased()
        let subtags = parts.dropFirst()

        // European or generic Portuguese is not a supported UI locale; preserve
        // the server's broad audience value instead of AppLanguage's UI fallback.
        if language == "pt" {
            return subtags.contains(where: { $0.lowercased() == "br" }) ? "pt-BR" : "pt"
        }

        if let knownLanguage = AppLanguage.match(normalizedSeparators) {
            return knownLanguage.rawValue
        }

        var result = language
        if let script = subtags.first,
           script.utf8.count == 4,
           script.utf8.allSatisfy(isASCIIAlpha) {
            let lowercasedScript = script.lowercased()
            result += "-" + lowercasedScript.prefix(1).uppercased() + lowercasedScript.dropFirst()
        }

        guard isValid(result), result.utf8.count <= 16 else { return nil }
        return result
    }

    private static func isValid(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 16 else { return false }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard let primary = parts.first,
              (2...8).contains(primary.utf8.count),
              primary.utf8.allSatisfy(isASCIIAlpha) else { return false }
        return parts.dropFirst().allSatisfy { part in
            (1...8).contains(part.utf8.count) && part.utf8.allSatisfy(isASCIIAlphaNumeric)
        }
    }

    private static func isASCIIAlpha(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte)
    }

    private static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        isASCIIAlpha(byte) || (48...57).contains(byte)
    }
}
