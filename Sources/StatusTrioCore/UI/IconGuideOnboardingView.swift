import SwiftUI

struct IconGuideOnboardingView: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: IconGuidePage = .anatomy
    let onCustomize: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(localization.string(.guideTitle))
                    .font(.title2.weight(.semibold))

                Spacer(minLength: 16)

                pageIndicator
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            Group {
                switch page {
                case .anatomy:
                    IconGuideView(settings: settings)
                case .states:
                    IconGuideStateGalleryView(settings: settings)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 640, height: 560)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            pageDot(for: .anatomy)
            pageDot(for: .states)
        }
        .accessibilityHidden(true)
    }

    private func pageDot(for item: IconGuidePage) -> some View {
        Circle()
            .fill(
                page == item
                    ? Color.accentColor
                    : Color.secondary.opacity(0.25)
            )
            .frame(width: 7, height: 7)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if page == .states {
                Button(localization.string(.commonBack)) {
                    show(.anatomy)
                }
            }

            Spacer(minLength: 8)

            if page == .states {
                Button(localization.string(.guideCustomize), action: onCustomize)
            }

            Button(
                localization.string(page == .anatomy ? .guideNext : .guideDone)
            ) {
                if page == .anatomy {
                    show(.states)
                } else {
                    onDone()
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }

    private func show(_ destination: IconGuidePage) {
        withAnimation(
            reduceMotion
                ? nil
                : .easeInOut(duration: 0.22)
        ) {
            page = destination
        }
    }
}
