import Foundation

enum AppMetadata {
    static let defaultName = "Status Trio"
    private static let nameKeys = ["CFBundleDisplayName", "CFBundleName"]
    private static let developmentCodenameKey = "STDevelopmentCodename"

    static var name: String {
        for key in nameKeys {
            if let value = validName(Bundle.main.object(forInfoDictionaryKey: key)) {
                return value
            }
        }
        return defaultName
    }

    static func name(from infoDictionary: [String: Any]) -> String {
        for key in nameKeys {
            if let value = validName(infoDictionary[key]) {
                return value
            }
        }
        return defaultName
    }

    static var developmentCodename: String? {
        developmentCodename(from: Bundle.main.infoDictionary ?? [:])
    }

    static func developmentCodename(from infoDictionary: [String: Any]) -> String? {
        validName(infoDictionary[developmentCodenameKey])
    }

    /// Whether this build bundled the privileged power helper.
    ///
    /// `build-app.sh` writes this from the `PRIVILEGED_HELPER` switch, so an
    /// App-Store-style build sets it false and the app hides the feature rather
    /// than offering a toggle that cannot work. Missing key reads as false.
    private static let includesPrivilegedHelperKey = "STIncludesPrivilegedHelper"

    static var includesPrivilegedHelper: Bool {
        includesPrivilegedHelper(from: Bundle.main.infoDictionary ?? [:])
    }

    static func includesPrivilegedHelper(from infoDictionary: [String: Any]) -> Bool {
        infoDictionary[includesPrivilegedHelperKey] as? Bool ?? false
    }

    private static func validName(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    static let repositoryDisplayName = "github.com/lingyired/status-trio"
    static let repositoryURL = URL(string: "https://github.com/lingyired/status-trio")!
    static let projectHomepageURL = URL(string: "https://statustrio.lingai.net/")!
    static let authorName = "lingyired"
    static let authorURL = URL(string: "https://github.com/lingyired")!
    static let authorWebsiteURL = URL(string: "https://lingai.net/")!

    static var versionDisplayString: String {
        versionDisplayString(from: Bundle.main.infoDictionary ?? [:])
    }

    static func versionDisplayString(from infoDictionary: [String: Any]) -> String {
        let version = infoDictionary["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = infoDictionary["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
