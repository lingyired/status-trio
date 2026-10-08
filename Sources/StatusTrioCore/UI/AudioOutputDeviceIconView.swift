import SwiftUI

struct AudioOutputDeviceIconView: View {
    let source: IconSymbolSource
    var glyphSize: CGFloat = 13

    var body: some View {
        PanelSymbolView(source: source, size: glyphSize, weight: .semibold)
            .frame(width: glyphSize, height: glyphSize)
    }
}
