import SwiftUI

struct IconGuideOnboardingView: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject private var localization: Localization
    let onCustomize: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localization.string(.guideTitle))
                .font(.title2.weight(.semibold))

            IconGuideView(settings: settings)

            HStack {
                Button(localization.string(.guideCustomize), action: onCustomize)
                Spacer(minLength: 8)
                Button(localization.string(.guideDone), action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480, alignment: .leading)
    }
}
