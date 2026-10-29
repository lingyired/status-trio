import Foundation

extension Bundle {
    /// Store compiles the shared sources into a framework, so SwiftPM's
    /// generated `Bundle.module` accessor is unavailable.
    static var module: Bundle {
        Bundle(for: StatusTrioResourceBundleAnchor.self)
    }
}
