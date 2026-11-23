import SwiftUI

enum IconDesignerSection: String, CaseIterable, Identifiable {
    case slot
    case source
    case behavior
    case appearance
    case presets

    var id: Self { self }
}

enum IconDesignerPreviewHitRegion: CaseIterable, Identifiable {
    case top
    case middle
    case bottom

    var id: Self { self }

    var slot: IconSlot {
        switch self {
        case .top: .outerRing
        case .middle: .center
        case .bottom: .footer
        }
    }
}

enum IconDesignerLayout {
    static let sectionOrder: [IconDesignerSection] = IconDesignerSection.allCases
    static let previewHitRegionWidth: CGFloat = 44
    static let minimumPreviewHitRegionHeight: CGFloat = 16
    static let maximumPinnedHeaderContentHeight: CGFloat = 88
    static let menuBarPreviewPointSize: CGFloat = 24
    static let dockPreviewPointSize: CGFloat = 128
    static let minimumLargePreviewPointSize: CGFloat = 240
    static let maximumLargePreviewPointSize: CGFloat = 300
    static let previewColumnRatio: CGFloat = 0.44
    static let inspectorColumnRatio: CGFloat = 0.56
    static let horizontalPadding: CGFloat = 20
    static let columnSpacing: CGFloat = 18

    static func columns(for width: CGFloat) -> (preview: CGFloat, inspector: CGFloat) {
        let availableWidth = max(0, width - 2 * horizontalPadding - columnSpacing)
        return (availableWidth * previewColumnRatio, availableWidth * inspectorColumnRatio)
    }

    static func largePreviewPointSize(for previewWidth: CGFloat) -> CGFloat {
        min(maximumLargePreviewPointSize, max(minimumLargePreviewPointSize, previewWidth * 0.72))
    }

    static func previewHitRegionHeight(forIconSize iconSize: CGFloat) -> CGFloat {
        max(minimumPreviewHitRegionHeight, ceil(iconSize / 3))
    }

}

extension IconSlot {
    var designerSymbol: String {
        switch self {
        case .outerRing: "circle.dashed"
        case .center: "circle.inset.filled"
        case .footer: "circle.bottomhalf.filled"
        }
    }
}
