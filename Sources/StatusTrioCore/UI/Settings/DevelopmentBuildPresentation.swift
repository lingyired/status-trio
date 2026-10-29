import Foundation

enum DevelopmentBuildPresentation {
    static func aboutSidebarDetail(version: String, codename: String?) -> String {
        let versionLabel = "v\(version)"
        guard let codename, !codename.isEmpty else { return versionLabel }
        return "\(versionLabel)\n\(codename)"
    }
}
