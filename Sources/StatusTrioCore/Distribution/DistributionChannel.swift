enum DistributionChannel: String, CaseIterable, Sendable {
    case direct
    case appStore

    static var current: Self {
        #if STATUS_TRIO_APP_STORE
        .appStore
        #else
        .direct
        #endif
    }

    var productionBundleIdentifier: String {
        switch self {
        case .direct: "com.lingsmbp.StatusTrio"
        case .appStore: "com.lingsmbp.StatusTrio.AppStore"
        }
    }
}
