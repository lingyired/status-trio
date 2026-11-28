import Foundation

/// Joins the network row's second line.
///
/// The address the user asked for leads, and whatever the row already said —
/// the Wi-Fi band and signal, or the wired port's state — follows it. Shared by
/// both links so the two paths cannot drift on the separator or on what an
/// absent piece of the line does.
enum NetworkRowSubtitle {
    /// The middle dot the network row already uses between its own clauses.
    static let separator = " · "

    static func prepending(_ prefix: String?, to text: String?) -> String? {
        let prefix = nonEmpty(prefix)
        let text = nonEmpty(text)
        switch (prefix, text) {
        case let (prefix?, text?):
            return prefix + separator + text
        case let (prefix?, nil):
            return prefix
        case let (nil, text?):
            return text
        case (nil, nil):
            return nil
        }
    }

    /// Trails an address behind text that already names the link state.
    static func appending(_ suffix: String?, to text: String?) -> String? {
        let text = nonEmpty(text)
        let suffix = nonEmpty(suffix)
        switch (text, suffix) {
        case let (text?, suffix?):
            return text + separator + suffix
        case let (text?, nil):
            return text
        case let (nil, suffix?):
            return suffix
        case (nil, nil):
            return nil
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
