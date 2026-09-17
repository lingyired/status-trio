import SwiftUI

struct IconGuideOnboardingView: View {
    static let contentWidth: CGFloat = 640
    static let footerHeight: CGFloat = 32

    @ObservedObject var settings: SettingsStore
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: IconGuidePage = .anatomy
    let onCustomize: () -> Void
    let onDone: () -> Void

    init(
        settings: SettingsStore,
        initialPage: IconGuidePage = .anatomy,
        onCustomize: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.settings = settings
        _page = State(initialValue: initialPage)
        self.onCustomize = onCustomize
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(localization.string(.guideTitle))
                    .font(.title2.weight(.semibold))

                Spacer(minLength: 16)

                pageIndicator
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            ZStack(alignment: .topLeading) {
                IconGuideView(settings: settings)
                    .opacity(page == .anatomy ? 1 : 0)
                    .allowsHitTesting(page == .anatomy)
                    .accessibilityHidden(page != .anatomy)

                IconGuideStateGalleryView(settings: settings)
                    .opacity(page == .states ? 1 : 0)
                    .allowsHitTesting(page == .states)
                    .accessibilityHidden(page != .states)
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Divider()

            footer
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 22)
        }
        .frame(width: Self.contentWidth)
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
            Button(localization.string(.commonBack)) {
                show(.anatomy)
            }
            .opacity(page == .states ? 1 : 0)
            .disabled(page != .states)
            .accessibilityHidden(page != .states)

            Spacer(minLength: 8)

            Button(localization.string(.guideCustomize), action: onCustomize)
                .opacity(page == .states ? 1 : 0)
                .disabled(page != .states)
                .accessibilityHidden(page != .states)

            primaryButton
        }
        .frame(height: Self.footerHeight)
    }

    private var primaryButton: some View {
        Button {
            if page == .anatomy {
                show(.states)
            } else {
                onDone()
            }
        } label: {
            ZStack {
                Text(localization.string(.guideNext))
                    .opacity(page == .anatomy ? 1 : 0)

                Text(localization.string(.guideDone))
                    .opacity(page == .states ? 1 : 0)
            }
        }
        .accessibilityLabel(
            localization.string(page == .anatomy ? .guideNext : .guideDone)
        )
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
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
