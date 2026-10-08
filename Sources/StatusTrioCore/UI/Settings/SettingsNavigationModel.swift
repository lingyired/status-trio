import SwiftUI

struct SettingsNavigationModel: Equatable {
    enum Page: String, CaseIterable, Identifiable, Equatable {
        case iconDesigner
        case battery
        case network
        case bluetooth
        case audio
        case popover
        case general
        case about

        var id: String { rawValue }

        var legacyFocus: DesignerFocus? {
            self == .iconDesigner ? .placement : nil
        }

        var symbol: String {
            switch self {
            case .iconDesigner: "macwindow.on.rectangle"
            case .battery: SymbolFallback.name("battery.100percent", "battery.100")
            case .network: "wifi"
            case .bluetooth: "wave.3.right.circle.fill"
            case .audio: "hifispeaker.fill"
            case .popover: "list.bullet.rectangle"
            case .general: "gearshape.fill"
            case .about: "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .iconDesigner: .indigo
            case .battery: .green
            case .network, .bluetooth: .blue
            case .audio: .cyan
            case .popover: .purple
            case .general: .gray
            case .about: .orange
            }
        }

        @MainActor
        func title(_ localization: Localization) -> String {
            switch self {
            case .iconDesigner: localization.string(.settingsTabAppIcon)
            case .battery: localization.string(.settingsTabBattery)
            case .network: localization.string(.settingsTabNetwork)
            case .bluetooth: localization.string(.settingsTabBluetooth)
            case .audio: localization.string(.settingsTabAudio)
            case .popover: localization.string(.settingsTabPanel)
            case .general: localization.string(.settingsPageGeneral)
            case .about: localization.string(.settingsTabAbout)
            }
        }
    }

    enum LegacyPage: Equatable {
        case appIcon
        case battery
        case network
        case bluetooth
        case audio
        case popover
        case general
        case about
    }

    enum DesignerFocus: Equatable {
        case placement
        case outerRing
        case center
        case footer
    }

    var selection: Page

    init(selection: Page = .iconDesigner) {
        self.selection = selection
    }

    static let devicePages: [Page] = [.battery, .network, .bluetooth, .audio]
    static let allPages = Page.allCases

    static func destination(forLegacyPage page: LegacyPage) -> Page {
        switch page {
        case .appIcon: .iconDesigner
        case .battery: .battery
        case .network: .network
        case .bluetooth: .bluetooth
        case .audio: .audio
        case .popover: .popover
        case .general: .general
        case .about: .about
        }
    }

    static func legacyFocus(for page: LegacyPage) -> DesignerFocus? {
        page == .appIcon ? .placement : nil
    }
}
